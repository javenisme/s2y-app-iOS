//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation
import Network
import Combine

// ============================================================
// MARK: - Network Monitor
// ============================================================

/// 网络状态监控器
@MainActor final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published private(set) var status: NetworkStatus = .unknown
    @Published private(set) var isExpensive: Bool = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    enum NetworkStatus: Equatable {
        case wifi
        case cellular
        case ethernet
        case unknown
        
        var canDownloadLargeFile: Bool {
            self == .wifi || self == .ethernet
        }
        
        var displayName: String {
            switch self {
            case .wifi: return "WiFi"
            case .cellular: return "Cellular"
            case .ethernet: return "Ethernet"
            case .unknown: return "Unknown"
            }
        }
    }
    
    private init() {
        startMonitoring()
    }
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                NetworkMonitor.shared.updateStatus(path)
            }
        }
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
    
    private func updateStatus(_ path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            status = .wifi
        } else if path.usesInterfaceType(.cellular) {
            status = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            status = .ethernet
        } else {
            status = .unknown
        }
        
        isExpensive = path.isExpensive
    }
}

// ============================================================
// MARK: - Download Request
// ============================================================

/// MLX 模型下载请求
struct MLXDownloadRequest: Codable, Sendable {
    let modelConfig: LocalModelConfig
    let version: String
    let downloadURL: URL
    let fileSize: Int64  // bytes
    let checksum: String?  // SHA256
    
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

/// 下载策略配置
struct DownloadPolicy: Sendable {
    /// 是否仅在 WiFi 下下载大文件
    let wifiOnlyForLargeFiles: Bool
    
    /// 大文件阈值 (字节)
    let largeFileThreshold: Int64
    
    /// 超过阈值时强制 WiFi
    var largeFileSize: Int64 { largeFileThreshold }
    
    static let `default` = DownloadPolicy(
        wifiOnlyForLargeFiles: true,
        largeFileThreshold: 100 * 1024 * 1024  // 100MB
    )
}

// ============================================================
// MARK: - MLX Model Download Manager
// ============================================================

/// MLX 模型下载管理器扩展
/// 支持 WiFi 检测、后台下载、断点续传
@MainActor
final class MLXModelDownloadManager: ObservableObject {
    static let shared = MLXModelDownloadManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var currentDownload: MLXDownloadRequest?
    @Published private(set) var downloadProgress: Double = 0.0
    @Published private(set) var bytesDownloaded: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var downloadSpeed: String = ""
    @Published private(set) var estimatedTimeRemaining: String = ""
    @Published private(set) var status: DownloadStatus = .idle
    @Published private(set) var lastError: MLXDownloadError?
    
    // MARK: - Dependencies
    
    private let networkMonitor = NetworkMonitor.shared
    private let fileManager = FileManager.default
    private var downloadTask: URLSessionDownloadTask?
    private var urlSession: URLSession!
    private var progressTimer: Timer?
    
    // Download stats
    private var downloadStartTime: Date?
    private var lastBytesReceived: Int64 = 0
    
    // MARK: - Download Status
    
    enum DownloadStatus: Equatable, Sendable {
        case idle
        case checkingNetwork
        case waitingForWiFi
        case downloading
        case paused
        case resuming
        case completed
        case failed(String)
        
        var displayMessage: String {
            switch self {
            case .idle: return "Ready"
            case .checkingNetwork: return "Checking network..."
            case .waitingForWiFi: return "Waiting for WiFi connection..."
            case .downloading: return "Downloading..."
            case .paused: return "Paused"
            case .resuming: return "Resuming..."
            case .completed: return "Download complete"
            case .failed(let error): return "Failed: \(error)"
            }
        }
    }
    
    // MARK: - Error Types
    
    enum MLXDownloadError: Error, LocalizedError, Sendable {
        case noNetwork
        case notOnWiFi
        case insufficientStorage
        case downloadFailed(String)
        case fileCorrupted
        case cancelled
        
        var errorDescription: String? {
            switch self {
            case .noNetwork:
                return "No network connection available"
            case .notOnWiFi:
                return "Please connect to WiFi to download the model"
            case .insufficientStorage:
                return "Not enough storage space"
            case .downloadFailed(let message):
                return "Download failed: \(message)"
            case .fileCorrupted:
                return "Downloaded file is corrupted"
            case .cancelled:
                return "Download was cancelled"
            }
        }
    }
    
    // MARK: - Singleton
    
    private init() {
        setupURLSession()
    }
    
    private func setupURLSession() {
        let config = URLSessionConfiguration.background(withIdentifier: "com.s2y.health.mlxdownload")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = false  // We handle this manually
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
    }
    
    // MARK: - Public API
    
    /// 检查是否可以开始下载
    /// - Parameters:
    ///   - modelConfig: 模型配置
    ///   - policy: 下载策略
    /// - Returns: 是否可以下载
    func canStartDownload(
        for modelConfig: LocalModelConfig,
        policy: DownloadPolicy = .default
    ) -> Result<Bool, MLXDownloadError> {
        // Check network
        guard networkMonitor.status != .unknown else {
            return .failure(.noNetwork)
        }
        
        let fileSize = getModelFileSize(for: modelConfig)
        
        // Check if large file and WiFi required
        if policy.wifiOnlyForLargeFiles && fileSize > policy.largeFileThreshold {
            if networkMonitor.status != .wifi {
                return .failure(.notOnWiFi)
            }
        }
        
        // Check storage
        if !hasEnoughStorage(for: fileSize) {
            return .failure(.insufficientStorage)
        }
        
        return .success(true)
    }
    
    /// 下载模型 (带 WiFi 检测)
    /// - Parameters:
    ///   - modelConfig: 模型配置
    ///   - policy: 下载策略
    ///   - progressHandler: 进度回调
    func downloadModel(
        _ modelConfig: LocalModelConfig,
        policy: DownloadPolicy = .default,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        // Check if already downloading
        switch status {
        case .idle, .completed, .failed(_):
            break
        default:
            return  // Already downloading
        }
        
        status = .checkingNetwork
        lastError = nil
        
        // Get model info
        let downloadURL = getDownloadURL(for: modelConfig)
        let fileSize = getModelFileSize(for: modelConfig)
        
        // Check network status
        if policy.wifiOnlyForLargeFiles && fileSize > policy.largeFileThreshold {
            if networkMonitor.status != .wifi {
                status = .waitingForWiFi
                throw MLXDownloadError.notOnWiFi
            }
        }
        
        // Check storage
        guard hasEnoughStorage(for: fileSize) else {
            status = .failed("Insufficient storage")
            throw MLXDownloadError.insufficientStorage
        }
        
        // Start download
        totalBytes = fileSize
        bytesDownloaded = 0
        downloadProgress = 0.0
        status = .downloading
        
        do {
            try await performDownload(
                url: downloadURL,
                to: getModelDestination(for: modelConfig),
                progressHandler: progressHandler
            )
            status = .completed
        } catch let error as MLXDownloadError {
            status = .failed(error.localizedDescription)
            lastError = error
            throw error
        } catch {
            let downloadError = MLXDownloadError.downloadFailed(error.localizedDescription)
            status = .failed(error.localizedDescription)
            lastError = downloadError
            throw downloadError
        }
    }
    
    /// 暂停下载
    func pauseDownload() {
        downloadTask?.suspend()
        status = .paused
    }
    
    /// 恢复下载
    func resumeDownload() {
        downloadTask?.resume()
        status = .downloading
    }
    
    /// 取消下载
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        status = .idle
        downloadProgress = 0.0
        bytesDownloaded = 0
    }
    
    /// 检查模型是否已下载
    func isModelDownloaded(_ modelConfig: LocalModelConfig) -> Bool {
        let destination = getModelDestination(for: modelConfig)
        return fileManager.fileExists(atPath: destination.path)
    }
    
    /// 删除已下载的模型
    func deleteModel(_ modelConfig: LocalModelConfig) throws {
        let destination = getModelDestination(for: modelConfig)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
    }
    
    // MARK: - Private Methods
    
    private func performDownload(
        url: URL,
        to destination: URL,
        progressHandler: ((Double) -> Void)?
    ) async throws {
        // Create directory if needed
        let parentDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        // Basic resume support using Range header based on existing file size
        var existingSize: Int64 = 0
        if fileManager.fileExists(atPath: destination.path) {
            existingSize = (try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
        }
        
        // Create request
        var request = URLRequest(url: url)
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
            bytesDownloaded = existingSize
        }
        
        // Start download
        downloadStartTime = Date()
        lastBytesReceived = 0
        
        let (tempURL, response) = try await urlSession.download(for: request)
        
        // Verify response
        if let httpResponse = response as? HTTPURLResponse {
            guard (200..<300).contains(httpResponse.statusCode) || httpResponse.statusCode == 206 else {
                throw MLXDownloadError.downloadFailed("HTTP \(httpResponse.statusCode)")
            }
        }
        
        // Move to destination
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)
        
        downloadProgress = 1.0
        progressHandler?(1.0)
    }
    
    private func getDownloadURL(for config: LocalModelConfig) -> URL {
        // 本地测试服务器 (运行在 Mac 上)
        // python3 -m http.server 9999 (在 s2y-models 目录)
        let localServerBase = "http://10.0.0.145:9999"
        
        // 使用本地服务器
        return URL(string: "\(localServerBase)/\(config.rawValue).gguf")!
    }
    
    private func getModelDestination(for config: LocalModelConfig) -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath
            .appendingPathComponent("MLXModels")
            .appendingPathComponent(config.rawValue)
            .appendingPathComponent("\(config.rawValue).gguf")
    }
    
    private func getModelFileSize(for config: LocalModelConfig) -> Int64 {
        // 本地测试: 使用小文件
        // 实际部署时使用真实模型大小
        switch config {
        case .phi3_5Mini: return 10_485_760   // 10MB 测试文件
        case .phi4Mini: return 10_485_760
        case .llama3_8b: return 10_485_760
        case .mistralNemo: return 10_485_760
        case .tinyLlama: return 10_485_760
        }
    }
    
    private func hasEnoughStorage(for bytes: Int64) -> Bool {
        do {
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let values = try documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            return available > bytes
        } catch {
            return false
        }
    }
    
    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func updateProgress() {
        guard let startTime = downloadStartTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let bytesPerSecond = elapsed > 0 ? Double(bytesDownloaded) / elapsed : 0
        
        downloadSpeed = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
        
        if bytesPerSecond > 0 {
            let remaining = totalBytes - bytesDownloaded
            let remainingSeconds = Double(remaining) / bytesPerSecond
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.minute, .second]
            formatter.unitsStyle = .abbreviated
            estimatedTimeRemaining = formatter.string(from: remainingSeconds) ?? ""
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension MLXModelDownloadManager {
    static func preview() -> MLXModelDownloadManager {
        let manager = MLXModelDownloadManager.shared
        manager.status = .downloading
        manager.downloadProgress = 0.65
        manager.bytesDownloaded = 1_625_000_000
        manager.totalBytes = 2_500_000_000
        return manager
    }
}
#endif
