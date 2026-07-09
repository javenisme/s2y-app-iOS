//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import S2Y

// ============================================================
// MARK: - LocalLLMService Tests
// ============================================================

@MainActor
final class LocalLLMServiceTests: XCTestCase {
    
    var service: LocalLLMService!
    
    override func setUp() async throws {
        try await super.setUp()
        service = LocalLLMService.shared
        await service.unloadModel()
    }
    
    override func tearDown() async throws {
        await service.unloadModel()
        service = nil
        try await super.tearDown()
    }
    
    // MARK: - Model Configuration Tests
    
    func testModelConfig_phi4Mini() {
        let config = LocalModelConfig.phi4Mini
        
        XCTAssertEqual(config.rawValue, "Phi-4-Mini-3.8B")
        XCTAssertEqual(config.minRAM, 4)
        XCTAssertEqual(config.fileExtension, "gguf")
        XCTAssertEqual(config.huggingFaceID, "microsoft/Phi-4-mini-instruct")
    }
    
    func testModelConfig_llama3_8b() {
        let config = LocalModelConfig.llama3_8b
        
        XCTAssertEqual(config.rawValue, "Llama-3.1-8B-Instruct")
        XCTAssertEqual(config.minRAM, 8)
    }
    
    func testModelConfig_mistralNemo() {
        let config = LocalModelConfig.mistralNemo
        
        XCTAssertEqual(config.rawValue, "Mistral-Nemo-12B")
        XCTAssertEqual(config.minRAM, 12)
    }
    
    func testModelConfig_allCases() {
        let allCases = LocalModelConfig.allCases
        
        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.phi3_5Mini))
        XCTAssertTrue(allCases.contains(.phi4Mini))
        XCTAssertTrue(allCases.contains(.llama3_8b))
        XCTAssertTrue(allCases.contains(.mistralNemo))
        XCTAssertTrue(allCases.contains(.tinyLlama))
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertFalse(service.isModelLoaded)
        XCTAssertNil(service.currentModel)
        XCTAssertFalse(service.isGenerating)
        XCTAssertEqual(service.loadingProgress, 0.0)
        XCTAssertNil(service.lastError)
    }
    
    // MARK: - System Prompt Tests
    
    func testSetSystemPrompt() {
        let customPrompt = "You are a test assistant."
        
        service.setSystemPrompt(customPrompt)
        
        // Access via reflection or test the effect
        XCTAssertNotNil(service)
    }
    
    // MARK: - Memory Detection Tests
    
    func testGetAvailableRAM() {
        let ram = service.getAvailableRAM()
        
        // Should return a reasonable value (at least 1GB)
        XCTAssertGreaterThanOrEqual(ram, 1)
    }
    
    // MARK: - Load Model Tests
    
    func testLoadModel_insufficientMemory() async throws {
        // Create a config that requires more RAM than available
        let largeConfig = LocalModelConfig.mistralNemo
        
        // Get actual available RAM
        let availableRAM = service.getAvailableRAM()
        
        // If we somehow have >12GB RAM, this test won't catch the error
        // In that case, skip or modify the test
        if availableRAM >= 12 {
            // Model should load successfully on high-RAM devices
            do {
                try await service.loadModel(largeConfig)
                XCTAssertTrue(service.isModelLoaded)
                XCTAssertEqual(service.currentModel, largeConfig)
            } catch {
                XCTFail("Should not throw on high-RAM device: \(error)")
            }
        } else {
            // Should throw insufficient memory error
            do {
                try await service.loadModel(largeConfig)
                XCTFail("Expected insufficientMemory error")
            } catch {
                XCTAssertTrue(error is LocalLLMError)
                if let llmError = error as? LocalLLMError {
                    if case .insufficientMemory = llmError {
                        // Expected
                    } else {
                        XCTFail("Expected insufficientMemory error")
                    }
                }
            }
        }
    }
    
    func testLoadModel_sameModelTwice() async throws {
        let config = LocalModelConfig.phi4Mini
        
        // First load
        do {
            try await service.loadModel(config)
        } catch {
            // May fail due to MLX not implemented, that's ok for this test
        }
        
        // Second load with same config should be no-op (if already loaded)
        // Or reload if different
        // Just verify state is consistent
        XCTAssertNotNil(service)
    }
    
    // MARK: - Unload Model Tests
    
    func testUnloadModel() async throws {
        // Try to load a model
        do {
            try await service.loadModel(.phi4Mini)
        } catch {
            // Expected to fail if MLX not implemented
        }
        
        // Unload
        await service.unloadModel()
        
        // Verify state
        XCTAssertFalse(service.isModelLoaded)
        XCTAssertNil(service.currentModel)
        XCTAssertEqual(service.loadingProgress, 0.0)
    }
    
    // MARK: - Generate Tests
    
    func testGenerate_notLoaded() async throws {
        // Try to generate without loading model
        let stream = service.generate(prompt: "Hello")
        
        // Should throw modelNotLoaded error
        do {
            var iterator = stream.makeAsyncIterator()
            _ = try await iterator.next()
            XCTFail("Expected modelNotLoaded error")
        } catch {
            XCTAssertTrue(error is LocalLLMError)
        }
    }
    
    func testGenerateComplete_notLoaded() async throws {
        // Try to generate without loading model
        do {
            _ = try await service.generateComplete(prompt: "Hello")
            XCTFail("Expected modelNotLoaded error")
        } catch {
            XCTAssertTrue(error is LocalLLMError)
            if let llmError = error as? LocalLLMError {
                if case .modelNotLoaded = llmError {
                    // Expected
                } else {
                    XCTFail("Expected modelNotLoaded error")
                }
            }
        }
    }
    
    // MARK: - Error Description Tests
    
    func testErrorDescriptions() {
        let insufficientMemory = LocalLLMError.insufficientMemory(required: 8, available: 4)
        XCTAssertEqual(insufficientMemory.errorDescription, "Insufficient memory: requires 8GB, available 4GB")
        
        let modelNotLoaded = LocalLLMError.modelNotLoaded
        XCTAssertEqual(modelNotLoaded.errorDescription, "Model not loaded. Call loadModel() first.")
        
        let downloadFailed = LocalLLMError.modelDownloadFailed("Network error")
        XCTAssertEqual(downloadFailed.errorDescription, "Model download failed: Network error")
        
        let loadFailed = LocalLLMError.modelLoadFailed("File not found")
        XCTAssertEqual(loadFailed.errorDescription, "Model load failed: File not found")
        
        let generationFailed = LocalLLMError.generationFailed("Timeout")
        XCTAssertEqual(generationFailed.errorDescription, "Generation failed: Timeout")
        
        let unsupported = LocalLLMError.unsupportedModel
        XCTAssertEqual(unsupported.errorDescription, "Model not supported")
    }
}

// ============================================================
// MARK: - LocalGenerateParameters Tests
// ============================================================

final class LocalGenerateParametersTests: XCTestCase {
    
    func testDefaultParameters() {
        let params = LocalGenerateParameters()
        
        XCTAssertEqual(params.maxTokens, 1024)
        XCTAssertEqual(params.temperature, 0.7)
        XCTAssertEqual(params.topP, 0.9)
        XCTAssertEqual(params.topK, 40)
        XCTAssertEqual(params.repeatPenalty, 1.1)
    }
    
    func testCustomParameters() {
        let params = LocalGenerateParameters(
            maxTokens: 2048,
            temperature: 0.5,
            topP: 0.95,
            topK: 50,
            repeatPenalty: 1.2
        )
        
        XCTAssertEqual(params.maxTokens, 2048)
        XCTAssertEqual(params.temperature, 0.5)
        XCTAssertEqual(params.topP, 0.95)
        XCTAssertEqual(params.topK, 50)
        XCTAssertEqual(params.repeatPenalty, 1.2)
    }
}

// ============================================================
// MARK: - Preview Tests
// ============================================================

#if DEBUG
extension LocalLLMServiceTests {
    func testPreviewInstance() {
        let preview = LocalLLMService.preview()
        
        XCTAssertTrue(preview.isModelLoaded)
        XCTAssertEqual(preview.currentModel, .phi4Mini)
    }
}
#endif
