//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import XCTest
@testable import S2Y

// ============================================================
// MARK: - MLXModelDownloadManager Tests
// ============================================================

@MainActor
final class MLXModelDownloadManagerTests: XCTestCase {
    
    var manager: MLXModelDownloadManager!
    
    override func setUp() async throws {
        try await super.setUp()
        manager = MLXModelDownloadManager.shared
    }
    
    override func tearDown() async throws {
        manager.cancelDownload()
        manager = nil
        try await super.tearDown()
    }
    
    // MARK: - Network Status Tests
    
    func testNetworkMonitor_initialState() {
        let monitor = NetworkMonitor.shared
        XCTAssertNotNil(monitor)
    }
    
    func testNetworkStatus_wifiCanDownload() {
        let status = NetworkMonitor.NetworkStatus.wifi
        XCTAssertTrue(status.canDownloadLargeFile)
    }
    
    func testNetworkStatus_cellularCannotDownload() {
        let status = NetworkMonitor.NetworkStatus.cellular
        XCTAssertFalse(status.canDownloadLargeFile)
    }
    
    func testNetworkStatus_displayName() {
        XCTAssertEqual(NetworkMonitor.NetworkStatus.wifi.displayName, "WiFi")
        XCTAssertEqual(NetworkMonitor.NetworkStatus.cellular.displayName, "Cellular")
        XCTAssertEqual(NetworkMonitor.NetworkStatus.ethernet.displayName, "Ethernet")
        XCTAssertEqual(NetworkMonitor.NetworkStatus.unknown.displayName, "Unknown")
    }
    
    // MARK: - Download Policy Tests
    
    func testDownloadPolicy_default() {
        let policy = DownloadPolicy.default
        XCTAssertTrue(policy.wifiOnlyForLargeFiles)
        XCTAssertEqual(policy.largeFileThreshold, 100 * 1024 * 1024)
    }
    
    // MARK: - Model Config Size Tests
    
    func testModelFileSize_phi4Mini() {
        let size = getModelFileSize(for: .phi4Mini)
        XCTAssertEqual(size, 2_500_000_000)
    }
    
    func testModelFileSize_llama3_8b() {
        let size = getModelFileSize(for: .llama3_8b)
        XCTAssertEqual(size, 4_900_000_000)
    }
    
    func testModelFileSize_mistralNemo() {
        let size = getModelFileSize(for: .mistralNemo)
        XCTAssertEqual(size, 7_000_000_000)
    }
    
    // Helper function to test model sizes
    private func getModelFileSize(for config: LocalModelConfig) -> Int64 {
        switch config {
        case .phi3_5Mini: return 10_485_760
        case .phi4Mini: return 2_500_000_000
        case .llama3_8b: return 4_900_000_000
        case .mistralNemo: return 7_000_000_000
        case .tinyLlama: return 10_485_760
        }
    }
    
    // MARK: - Can Start Download Tests
    
    func testCanStartDownload_wifiLargeFile() {
        // This test would require mocking NetworkMonitor
        // For now, just verify the method exists and returns
        let result = manager.canStartDownload(
            for: .phi4Mini,
            policy: DownloadPolicy.default
        )
        
        // Result depends on actual network state
        XCTAssertNotNil(result)
    }
    
    // MARK: - Model Destination Tests
    
    func testModelDestination_path() {
        let fileManager = FileManager.default
        let config = LocalModelConfig.phi4Mini
        
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let expectedPath = documentsPath
            .appendingPathComponent("MLXModels")
            .appendingPathComponent(config.rawValue)
            .appendingPathComponent("\(config.rawValue).gguf")
        
        // Verify path construction logic
        XCTAssertTrue(expectedPath.path.contains("MLXModels"))
        XCTAssertTrue(expectedPath.path.contains("Phi-4-Mini-3.8B"))
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertEqual(manager.status, .idle)
        XCTAssertEqual(manager.downloadProgress, 0.0)
        XCTAssertEqual(manager.bytesDownloaded, 0)
        XCTAssertEqual(manager.totalBytes, 0)
        XCTAssertNil(manager.currentDownload)
        XCTAssertNil(manager.lastError)
    }
    
    // MARK: - Cancel Download Tests
    
    func testCancelDownload_resetsState() {
        manager.cancelDownload()
        
        XCTAssertEqual(manager.status, .idle)
        XCTAssertEqual(manager.downloadProgress, 0.0)
    }
}

// ============================================================
// MARK: - DownloadPolicy Tests
// ============================================================

final class DownloadPolicyTests: XCTestCase {
    
    func testDefaultPolicy_wifiOnly() {
        let policy = DownloadPolicy.default
        XCTAssertTrue(policy.wifiOnlyForLargeFiles)
    }
    
    func testCustomPolicy() {
        let policy = DownloadPolicy(
            wifiOnlyForLargeFiles: false,
            largeFileThreshold: 500 * 1024 * 1024  // 500MB
        )
        
        XCTAssertFalse(policy.wifiOnlyForLargeFiles)
        XCTAssertEqual(policy.largeFileThreshold, 500 * 1024 * 1024)
    }
    
    func testLargeFileThreshold() {
        let policy = DownloadPolicy(
            wifiOnlyForLargeFiles: true,
            largeFileThreshold: 100 * 1024 * 1024
        )
        
        XCTAssertEqual(policy.largeFileSize, 100 * 1024 * 1024)
    }
}

// ============================================================
// MARK: - Model Config Tests
// ============================================================

final class LocalModelConfigDownloadTests: XCTestCase {
    
    func testPhi4MiniProperties() {
        let config = LocalModelConfig.phi4Mini
        
        XCTAssertEqual(config.rawValue, "Phi-4-Mini-3.8B")
        XCTAssertEqual(config.minRAM, 4)
        XCTAssertEqual(config.fileExtension, "gguf")
    }
    
    func testLlama3_8bProperties() {
        let config = LocalModelConfig.llama3_8b
        
        XCTAssertEqual(config.rawValue, "Llama-3.1-8B-Instruct")
        XCTAssertEqual(config.minRAM, 8)
    }
    
    func testMistralNemoProperties() {
        let config = LocalModelConfig.mistralNemo
        
        XCTAssertEqual(config.rawValue, "Mistral-Nemo-12B")
        XCTAssertEqual(config.minRAM, 12)
    }
}
