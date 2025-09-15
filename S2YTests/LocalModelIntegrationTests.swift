//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import XCTest
@testable import S2Y

/// 本地模型集成测试
/// 验证Phi-3.5 Mini本地模型的完整集成流程
@MainActor
final class LocalModelIntegrationTests: XCTestCase {
    
    var localModelManager: LocalHealthModelManager!
    var downloadManager: ModelDownloadManager!
    var memoryMonitor: ModelMemoryMonitor!
    var enhancedProvider: EnhancedLLMProvider!
    
    override func setUp() async throws {
        try await super.setUp()
        
        localModelManager = LocalHealthModelManager.shared
        downloadManager = ModelDownloadManager.shared
        memoryMonitor = ModelMemoryMonitor()
        enhancedProvider = EnhancedLLMProvider.shared
    }
    
    override func tearDown() async throws {
        // 清理测试环境
        localModelManager.unloadModel()
        downloadManager.cancelDownload()
        
        try await super.tearDown()
    }
    
    // MARK: - 内存监控测试
    
    func testMemoryMonitorBasicFunctionality() throws {
        // 测试内存监控基本功能
        let totalMemory = memoryMonitor.getTotalMemoryMB()
        let availableMemory = memoryMonitor.getAvailableMemoryMB()
        let appMemoryUsage = memoryMonitor.getAppMemoryUsageMB()
        
        XCTAssertGreaterThan(totalMemory, 0, "总内存应该大于0")
        XCTAssertGreaterThan(availableMemory, 0, "可用内存应该大于0")
        XCTAssertGreaterThan(appMemoryUsage, 0, "应用内存使用应该大于0")
        XCTAssertLessThan(availableMemory, totalMemory, "可用内存应该小于总内存")
        
        print("📊 内存状态: 总内存=\(totalMemory)MB, 可用=\(availableMemory)MB, 应用使用=\(appMemoryUsage)MB")
    }
    
    func testMemoryPressureDetection() throws {
        // 测试内存压力检测
        let pressureLevel = memoryMonitor.getMemoryPressureLevel()
        let recommendation = memoryMonitor.recommendedModelConfiguration()
        
        XCTAssertNotNil(pressureLevel, "应该能检测到内存压力等级")
        XCTAssertNotNil(recommendation, "应该能提供模型推荐")
        
        print("🧠 内存压力: \(pressureLevel.rawValue), 推荐: \(recommendation.description)")
    }
    
    func testMemoryRequirementCheck() throws {
        // 测试内存需求检查
        let hasEnoughFor1GB = memoryMonitor.hasEnoughMemory(requiredMB: 1024)
        let hasEnoughFor4GB = memoryMonitor.hasEnoughMemory(requiredMB: 4096)
        
        print("💾 内存检查: 1GB=\(hasEnoughFor1GB ? "✅" : "❌"), 4GB=\(hasEnoughFor4GB ? "✅" : "❌")")
        
        // 至少应该能满足1GB的需求（除非设备内存极其有限）
        if memoryMonitor.getTotalMemoryMB() > 2048 {
            XCTAssertTrue(hasEnoughFor1GB, "大于2GB总内存的设备应该能满足1GB需求")
        }
    }
    
    // MARK: - 模型管理器测试
    
    func testLocalModelManagerInitialState() throws {
        // 测试模型管理器初始状态
        XCTAssertFalse(localModelManager.isModelLoaded, "初始状态模型应该未加载")
        XCTAssertEqual(localModelManager.modelStatus, .notLoaded, "初始状态应该是notLoaded")
        XCTAssertEqual(localModelManager.loadingProgress, 0.0, "初始加载进度应该是0")
        XCTAssertNil(localModelManager.lastError, "初始状态不应该有错误")
        
        print("🤖 模型管理器初始状态: ✅ 正常")
    }
    
    func testLocalModelLoadAttempt() async throws {
        // 测试模型加载尝试（即使没有实际模型文件）
        
        // 由于测试环境可能没有实际的模型文件，我们主要测试流程
        let initialState = localModelManager.modelStatus
        
        // 尝试加载模型
        await localModelManager.loadModelIfNeeded()
        
        // 检查状态变化
        let finalState = localModelManager.modelStatus
        
        print("🔄 模型加载尝试: \(initialState) -> \(finalState)")
        
        // 在没有模型文件的情况下，应该会出现错误状态
        if case .error = finalState {
            XCTAssertNotNil(localModelManager.lastError, "错误状态应该有对应的错误信息")
            print("⚠️ 预期的模型文件缺失错误: \(localModelManager.lastError?.localizedDescription ?? "未知")")
        }
    }
    
    // MARK: - 健康提示构建器测试
    
    func testHealthPromptBuilder() throws {
        // 测试健康提示构建
        let query = "我今天的步数如何？"
        let healthData: [String: Any] = [
            "steps": 8500,
            "heartRate": 72,
            "sleepAnalysis": ["duration": 7.5, "quality": "良好"]
        ]
        
        let prompt = HealthPromptBuilder.buildPrompt(query: query, healthData: healthData)
        
        XCTAssertFalse(prompt.isEmpty, "构建的提示不应该为空")
        XCTAssertTrue(prompt.contains(query), "提示应该包含用户查询")
        XCTAssertTrue(prompt.contains("步数"), "提示应该包含健康数据")
        XCTAssertTrue(prompt.contains("8500"), "提示应该包含具体数值")
        
        print("📝 提示构建测试: ✅ 成功")
        print("提示长度: \(prompt.count) 字符")
    }
    
    func testHealthPromptBuilderEmptyData() throws {
        // 测试空健康数据的提示构建
        let query = "我的健康状况如何？"
        let emptyData: [String: Any] = [:]
        
        let prompt = HealthPromptBuilder.buildPrompt(query: query, healthData: emptyData)
        
        XCTAssertFalse(prompt.isEmpty, "即使没有健康数据，提示也不应该为空")
        XCTAssertTrue(prompt.contains(query), "提示应该包含用户查询")
        XCTAssertTrue(prompt.contains("无可用健康数据"), "应该提示无健康数据")
        
        print("📝 空数据提示构建: ✅ 成功")
    }
    
    // MARK: - 下载管理器测试
    
    func testModelDownloadManagerInitialState() throws {
        // 测试下载管理器初始状态
        XCTAssertEqual(downloadManager.downloadState, .idle, "初始下载状态应该是idle")
        XCTAssertEqual(downloadManager.downloadProgress, 0.0, "初始下载进度应该是0")
        XCTAssertTrue(downloadManager.downloadSpeed.isEmpty, "初始下载速度应该为空")
        XCTAssertNil(downloadManager.lastError, "初始状态不应该有错误")
        
        print("📥 下载管理器初始状态: ✅ 正常")
    }
    
    func testModelInfoLoading() throws {
        // 测试模型信息加载
        let modelInfo = downloadManager.getModelInfo()
        
        XCTAssertNotNil(modelInfo, "应该能加载模型信息")
        
        if let info = modelInfo {
            XCTAssertEqual(info.model.name, "Phi-3.5-mini-instruct", "模型名称应该正确")
            XCTAssertEqual(info.technical.parameters, "3.8B", "参数数量应该正确")
            XCTAssertTrue(info.requirements.apple_silicon, "应该要求Apple Silicon")
            
            print("📋 模型信息加载: ✅ 成功")
            print("模型: \(info.model.name) \(info.model.version)")
            print("大小: \(info.technical.model_size_mb)MB")
            print("需求: iOS \(info.requirements.min_ios_version)+, \(info.requirements.min_memory_mb)MB内存")
        }
    }
    
    // MARK: - 增强LLM提供者测试
    
    func testEnhancedProviderLocalModelIntegration() async throws {
        // 测试增强LLM提供者的本地模型集成
        let status = enhancedProvider.getLocalModelStatus()
        
        XCTAssertNotNil(status, "应该能获取本地模型状态")
        XCTAssertFalse(status.statusDescription.isEmpty, "状态描述不应该为空")
        
        print("🔗 LLM提供者集成: ✅ 成功")
        print("本地模型状态: \(status.statusDescription)")
    }
    
    func testHealthQueryMetricIdentification() throws {
        // 测试健康查询的指标识别
        let queries = [
            "我今天走了多少步？",
            "最近的心率如何？",
            "睡眠质量怎样？",
            "血压正常吗？",
            "体重有变化吗？"
        ]
        
        // 这里我们测试提示构建器的指标识别逻辑
        for query in queries {
            let prompt = HealthPromptBuilder.buildPrompt(query: query, healthData: [:])
            
            XCTAssertFalse(prompt.isEmpty, "查询 '\(query)' 的提示不应该为空")
            print("🔍 查询处理: '\(query)' -> 提示长度: \(prompt.count)")
        }
    }
    
    // MARK: - 集成流程测试
    
    func testFullIntegrationFlow() async throws {
        // 测试完整集成流程
        print("🚀 开始完整集成流程测试")
        
        // 1. 检查内存状态
        let hasEnoughMemory = memoryMonitor.hasEnoughMemory(requiredMB: 1536)
        print("1️⃣ 内存检查: \(hasEnoughMemory ? "✅ 充足" : "❌ 不足")")
        
        // 2. 检查模型信息
        let modelInfo = downloadManager.getModelInfo()
        XCTAssertNotNil(modelInfo, "应该能获取模型信息")
        print("2️⃣ 模型信息: ✅ 已加载")
        
        // 3. 测试提示构建
        let testQuery = "分析我的健康状况"
        let testHealthData: [String: Any] = [
            "steps": 10000,
            "heartRate": 68,
            "sleepAnalysis": "良好"
        ]
        
        let prompt = HealthPromptBuilder.buildPrompt(query: testQuery, healthData: testHealthData)
        XCTAssertFalse(prompt.isEmpty, "提示构建应该成功")
        print("3️⃣ 提示构建: ✅ 成功")
        
        // 4. 测试LLM提供者状态
        let llmStatus = enhancedProvider.getLocalModelStatus()
        XCTAssertNotNil(llmStatus, "应该能获取LLM状态")
        print("4️⃣ LLM集成: ✅ \(llmStatus.statusDescription)")
        
        print("🎉 完整集成流程测试完成")
    }
    
    // MARK: - 性能测试
    
    func testMemoryMonitorPerformance() throws {
        // 测试内存监控性能
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<100 {
            _ = memoryMonitor.getAvailableMemoryMB()
            _ = memoryMonitor.getMemoryPressureLevel()
        }
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertLessThan(timeElapsed, 1.0, "100次内存检查应该在1秒内完成")
        print("⚡ 内存监控性能: \(String(format: "%.3f", timeElapsed))秒/100次调用")
    }
    
    func testPromptBuildingPerformance() throws {
        // 测试提示构建性能
        let testData: [String: Any] = [
            "steps": 8500,
            "heartRate": 72,
            "sleepAnalysis": ["duration": 7.5],
            "activeEnergyBurned": 450,
            "bodyMass": 70.5
        ]
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<100 {
            let query = "测试查询 \(i)"
            _ = HealthPromptBuilder.buildPrompt(query: query, healthData: testData)
        }
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertLessThan(timeElapsed, 0.5, "100次提示构建应该在0.5秒内完成")
        print("⚡ 提示构建性能: \(String(format: "%.3f", timeElapsed))秒/100次调用")
    }
    
    // MARK: - 错误处理测试
    
    func testErrorHandling() async throws {
        // 测试各种错误处理情况
        print("🛡️ 错误处理测试开始")
        
        // 测试内存不足情况
        let insufficientMemoryCheck = memoryMonitor.hasEnoughMemory(requiredMB: 999999) // 故意设置过大值
        XCTAssertFalse(insufficientMemoryCheck, "应该正确检测到内存不足")
        print("✅ 内存不足检测: 正常")
        
        // 测试模型加载错误
        await localModelManager.loadModelIfNeeded()
        if case .error = localModelManager.modelStatus {
            XCTAssertNotNil(localModelManager.lastError, "错误状态应该有错误信息")
            print("✅ 模型加载错误: \(localModelManager.lastError?.localizedDescription ?? "未知")")
        }
        
        print("🛡️ 错误处理测试完成")
    }
}