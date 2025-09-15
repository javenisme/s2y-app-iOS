//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import OSLog
import Network
import CryptoKit

/// 模型下载管理器
/// 负责从远程服务器下载和验证本地AI模型文件
@MainActor
final class ModelDownloadManager: ObservableObject {
    static let shared = ModelDownloadManager()
    
    // MARK: - Published Properties
    @Published private(set) var downloadState: DownloadState = .idle
    @Published private(set) var downloadProgress: Double = 0.0
    @Published private(set) var downloadSpeed: String = ""
    @Published private(set) var estimatedTimeRemaining: String = ""
    @Published private(set) var lastError: DownloadError?
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "S2Y", category: "ModelDownload")
    private let fileManager = FileManager.default
    private var downloadTask: URLSessionDownloadTask?
    private var downloadSession: URLSession?
    private var progressTimer: Timer?
    
    // 下载统计
    private var downloadStartTime: Date?
    private var lastBytesReceived: Int64 = 0
    private var totalBytesReceived: Int64 = 0
    
    private init() {
        setupDownloadSession()
    }
    
    enum DownloadState: Equatable {
        case idle           // 空闲状态
        case checking       // 检查文件状态
        case downloading    // 正在下载
        case validating     // 验证文件完整性
        case completed      // 下载完成
        case failed(String) // 下载失败
        
        var description: String {
            switch self {
            case .idle:
                return "准备下载"
            case .checking:
                return "检查模型文件"
            case .downloading:
                return "正在下载模型"
            case .validating:
                return "验证文件完整性"
            case .completed:
                return "下载完成"
            case .failed(let message):
                return "下载失败: \(message)"
            }
        }
    }
    
    // MARK: - Public API
    
    /// 检查并下载必要的模型文件
    func downloadModelIfNeeded() async throws {
        logger.info("Starting model download check")
        
        guard downloadState == .idle else {
            logger.warning("Download already in progress")
            return
        }
        
        downloadState = .checking
        
        do {
            // 检查本地文件是否存在且完整
            let localFilesValid = await checkLocalFiles()
            
            if localFilesValid {
                logger.info("Local model files are valid, no download needed")
                downloadState = .completed
                return
            }
            
            // 开始下载模型文件
            try await downloadModelFiles()
            
        } catch {
            let downloadError = error as? DownloadError ?? DownloadError.unknown(error.localizedDescription)
            lastError = downloadError
            downloadState = .failed(downloadError.localizedDescription)
            logger.error("Model download failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// 取消当前下载
    func cancelDownload() {
        logger.info("Canceling model download")
        
        downloadTask?.cancel()
        downloadTask = nil
        progressTimer?.invalidate()
        progressTimer = nil
        
        downloadState = .idle
        downloadProgress = 0.0
        resetDownloadStats()
    }
    
    /// 获取模型信息
    func getModelInfo() -> ModelInfo? {
        do {
            let modelInfoURL = getLocalModelInfoURL()
            let data = try Data(contentsOf: modelInfoURL)
            return try JSONDecoder().decode(ModelInfo.self, from: data)
        } catch {
            logger.error("Failed to load model info: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Private Implementation
    
    private func setupDownloadSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 3600.0 // 1 hour for large files
        config.allowsCellularAccess = false // WiFi only for model downloads
        
        downloadSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
    }
    
    private func checkLocalFiles() async -> Bool {
        guard let modelInfo = getModelInfo() else {
            logger.warning("Model info not found")
            return false
        }
        
        let localDir = getLocalModelDirectory()
        
        // 检查所有必要文件是否存在
        let requiredFiles = [
            modelInfo.files.model_file,
            modelInfo.files.tokenizer_file,
            modelInfo.files.config_file
        ]
        
        for filename in requiredFiles {
            let fileURL = localDir.appendingPathComponent(filename)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                logger.info("Missing file: \(filename)")
                return false
            }
        }
        
        // 验证文件完整性（如果有校验和）
        if await !validateFileIntegrity() {
            logger.warning("File integrity validation failed")
            return false
        }
        
        logger.info("All local model files are valid")
        return true
    }
    
    private func downloadModelFiles() async throws {
        guard let modelInfo = getModelInfo() else {
            throw DownloadError.configurationError("Model info not found")
        }
        
        logger.info("Starting model files download")
        downloadState = .downloading
        downloadStartTime = Date()
        
        let baseURL = modelInfo.deployment.download_url
        let localDir = getLocalModelDirectory()
        
        // 确保本地目录存在
        try fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)
        
        let filesToDownload = [
            modelInfo.files.model_file,
            modelInfo.files.tokenizer_file,
            modelInfo.files.config_file
        ]
        
        for (index, filename) in filesToDownload.enumerated() {
            let remoteURL = URL(string: baseURL + filename)!
            let localURL = localDir.appendingPathComponent(filename)
            
            logger.info("Downloading \(filename) from \(remoteURL)")
            
            try await downloadFile(from: remoteURL, to: localURL)
            
            // 更新总体进度
            downloadProgress = Double(index + 1) / Double(filesToDownload.count)
        }
        
        // 验证下载的文件
        downloadState = .validating
        
        if await !validateFileIntegrity() {
            throw DownloadError.validationError("Downloaded files failed integrity check")
        }
        
        downloadState = .completed
        logger.info("Model download completed successfully")
    }
    
    private func downloadFile(from remoteURL: URL, to localURL: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            downloadTask = downloadSession?.downloadTask(with: remoteURL) { [weak self] tempURL, response, error in
                
                if let error = error {
                    continuation.resume(throwing: DownloadError.networkError(error.localizedDescription))
                    return
                }
                
                guard let tempURL = tempURL else {
                    continuation.resume(throwing: DownloadError.unknown("No temp file URL"))
                    return
                }
                
                do {
                    // 移动临时文件到目标位置（避免跨 actor 访问，直接使用 FileManager.default）
                    let fm = FileManager.default
                    if fm.fileExists(atPath: localURL.path) {
                        try fm.removeItem(at: localURL)
                    }
                    try fm.moveItem(at: tempURL, to: localURL)

                    Logger(subsystem: "S2Y", category: "ModelDownload").info("Successfully downloaded \(localURL.lastPathComponent)")
                    continuation.resume()

                } catch {
                    continuation.resume(throwing: DownloadError.fileSystemError(error.localizedDescription))
                }
            }
            
            downloadTask?.resume()
        }
    }
    
    private func validateFileIntegrity() async -> Bool {
        // 这里应该实现实际的文件校验逻辑
        // 可以使用SHA256或其他校验方法
        logger.info("Validating file integrity")
        
        guard let modelInfo = getModelInfo() else {
            return false
        }
        
        let localDir = getLocalModelDirectory()
        let modelFile = localDir.appendingPathComponent(modelInfo.files.model_file)
        
        // 检查主模型文件大小是否合理
        do {
            let attributes = try fileManager.attributesOfItem(atPath: modelFile.path)
            if let fileSize = attributes[.size] as? Int64 {
                let expectedSizeMB = Int64(modelInfo.technical.model_size_mb)
                let expectedSizeBytes = expectedSizeMB * 1024 * 1024
                let tolerance = expectedSizeBytes / 10 // 10% tolerance
                
                if abs(fileSize - expectedSizeBytes) > tolerance {
                    logger.error("Model file size validation failed. Expected: ~\(expectedSizeMB)MB, Got: \(fileSize / 1024 / 1024)MB")
                    return false
                }
            }
        } catch {
            logger.error("Failed to check file attributes: \(error)")
            return false
        }
        
        logger.info("File integrity validation passed")
        return true
    }
    
    private func getLocalModelDirectory() -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("LocalModels")
    }
    
    private func getLocalModelInfoURL() -> URL {
        guard let url = Bundle.main.url(forResource: "model_info", withExtension: "json", subdirectory: "LocalModels") else {
            fatalError("model_info.json not found in bundle")
        }
        return url
    }
    
    private func resetDownloadStats() {
        downloadStartTime = nil
        lastBytesReceived = 0
        totalBytesReceived = 0
        downloadSpeed = ""
        estimatedTimeRemaining = ""
    }
    
    private func updateDownloadStats(bytesReceived: Int64, totalBytes: Int64) {
        totalBytesReceived = bytesReceived
        downloadProgress = Double(bytesReceived) / Double(totalBytes)
        
        guard let startTime = downloadStartTime else { return }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        let bytesPerSecond = Double(bytesReceived) / elapsedTime
        
        // 计算下载速度
        if bytesPerSecond > 1024 * 1024 {
            downloadSpeed = String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        } else {
            downloadSpeed = String(format: "%.1f KB/s", bytesPerSecond / 1024)
        }
        
        // 估算剩余时间
        let remainingBytes = totalBytes - bytesReceived
        let remainingTime = Double(remainingBytes) / bytesPerSecond
        
        if remainingTime < 60 {
            estimatedTimeRemaining = String(format: "%.0f秒", remainingTime)
        } else {
            estimatedTimeRemaining = String(format: "%.0f分钟", remainingTime / 60)
        }
    }
}

// MARK: - Data Types

enum DownloadError: LocalizedError {
    case networkError(String)
    case fileSystemError(String)
    case validationError(String)
    case configurationError(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "网络错误: \(message)"
        case .fileSystemError(let message):
            return "文件系统错误: \(message)"
        case .validationError(let message):
            return "文件验证错误: \(message)"
        case .configurationError(let message):
            return "配置错误: \(message)"
        case .unknown(let message):
            return "未知错误: \(message)"
        }
    }
}

struct ModelInfo: Codable {
    let model: ModelDetails
    let technical: TechnicalSpecs
    let requirements: SystemRequirements
    let files: ModelFiles
    let deployment: DeploymentConfig
    
    struct ModelDetails: Codable {
        let name: String
        let version: String
        let provider: String
        let description: String
        let languages: [String]
        let specialization: String
    }
    
    struct TechnicalSpecs: Codable {
        let architecture: String
        let parameters: String
        let quantization: String
        let model_size_mb: Int
        let context_length: Int
        let max_tokens: Int
    }
    
    struct SystemRequirements: Codable {
        let min_ios_version: String
        let min_memory_mb: Int
        let min_storage_mb: Int
        let apple_silicon: Bool
    }
    
    struct ModelFiles: Codable {
        let model_file: String
        let tokenizer_file: String
        let config_file: String
    }
    
    struct DeploymentConfig: Codable {
        let bundle_in_app: Bool
        let download_on_demand: Bool
        let download_url: String
        let auto_update: Bool
    }
}