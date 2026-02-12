//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import UIKit
import OSLog
import Darwin.Mach

/// 模型内存监控器
/// 负责监控设备内存状态，确保本地模型安全运行
class ModelMemoryMonitor {
    private let logger = Logger(subsystem: "S2Y", category: "MemoryMonitor")
    
    /// 检查是否有足够内存加载模型
    func hasEnoughMemory(requiredMB: Int) -> Bool {
        let availableMemory = getAvailableMemoryMB()
        let totalMemory = getTotalMemoryMB()
        let safetyFactor = 1.5 // 50%安全余量
        
        let hasEnough = Double(availableMemory) > Double(requiredMB) * safetyFactor
        
        logger.info("""
        Memory check: \
        Available: \(availableMemory)MB, \
        Required: \(requiredMB)MB, \
        Total: \(totalMemory)MB, \
        Result: \(hasEnough ? "✅ Sufficient" : "❌ Insufficient")
        """)
        
        return hasEnough
    }
    
    /// 获取可用内存(MB)
    func getAvailableMemoryMB() -> Int {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = getUsedMemory()
        let availableBytes = totalMemory - usedMemory
        
        return Int(availableBytes / (1024 * 1024))
    }
    
    /// 获取总内存(MB)
    func getTotalMemoryMB() -> Int {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        return Int(totalBytes / (1024 * 1024))
    }
    
    /// 获取当前内存压力等级
    func getMemoryPressureLevel() -> MemoryPressureLevel {
        let availableMemory = getAvailableMemoryMB()
        let totalMemory = getTotalMemoryMB()
        let usagePercentage = Double(totalMemory - availableMemory) / Double(totalMemory)
        
        switch usagePercentage {
        case 0.0..<0.6:
            return .normal
        case 0.6..<0.8:
            return .moderate
        case 0.8..<0.9:
            return .high
        default:
            return .critical
        }
    }
    
    /// 获取应用当前使用的内存(MB)
    func getAppMemoryUsageMB() -> Int {
        let usedBytes = getUsedMemory()
        return Int(usedBytes / (1024 * 1024))
    }
    
    /// 注册内存警告观察者
    func registerMemoryWarningObserver(callback: @escaping () -> Void) {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.logger.warning("Memory warning received from system")
            callback()
        }
    }
    
    /// 监控内存使用情况
    func startMemoryMonitoring(interval: TimeInterval = 30.0, callback: @escaping (MemoryStatus) -> Void) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let status = self.getCurrentMemoryStatus()
            callback(status)
            
            if status.pressureLevel == .high || status.pressureLevel == .critical {
                self.logger.warning("High memory pressure detected: \(status)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// 获取已使用内存大小(字节)
    private func getUsedMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
    
    /// 获取当前内存状态
    private func getCurrentMemoryStatus() -> MemoryStatus {
        let totalMB = getTotalMemoryMB()
        let availableMB = getAvailableMemoryMB()
        let usedMB = totalMB - availableMB
        let appUsageMB = getAppMemoryUsageMB()
        let pressureLevel = getMemoryPressureLevel()
        
        return MemoryStatus(
            totalMB: totalMB,
            availableMB: availableMB,
            usedMB: usedMB,
            appUsageMB: appUsageMB,
            pressureLevel: pressureLevel
        )
    }
}

// MARK: - Data Types

/// 内存压力等级
enum MemoryPressureLevel: String, CaseIterable {
    case normal = "Normal"
    case moderate = "Moderate"
    case high = "High"
    case critical = "Critical"
    
    var description: String {
        switch self {
        case .normal:
            return "Memory usage is normal. Safe to load local model."
        case .moderate:
            return "Memory usage is moderate. Load model with caution."
        case .high:
            return "Memory usage is high. Large models are not recommended."
        case .critical:
            return "Memory usage is critical. Free memory before loading a model."
        }
    }
    
    var shouldLoadModel: Bool {
        switch self {
        case .normal, .moderate:
            return true
        case .high, .critical:
            return false
        }
    }
}

/// 内存状态信息
struct MemoryStatus: CustomStringConvertible {
    let totalMB: Int
    let availableMB: Int
    let usedMB: Int
    let appUsageMB: Int
    let pressureLevel: MemoryPressureLevel
    
    var usagePercentage: Double {
        Double(usedMB) / Double(totalMB) * 100
    }
    
    var description: String {
        """
        Memory Status:
        - Total: \(totalMB)MB
        - Available: \(availableMB)MB
        - Used: \(usedMB)MB (\(String(format: "%.1f", usagePercentage))%)
        - App Usage: \(appUsageMB)MB
        - Pressure: \(pressureLevel.rawValue)
        """
    }
}

// MARK: - Memory Optimization Helpers

extension ModelMemoryMonitor {
    
    /// 建议的模型配置基于当前内存状态
    func recommendedModelConfiguration() -> ModelSizeRecommendation {
        let availableMB = getAvailableMemoryMB()
        let pressureLevel = getMemoryPressureLevel()
        
        switch (availableMB, pressureLevel) {
        case (3000..., .normal):
            return .large // 可加载大模型
        case (2000..<3000, .normal), (2500..., .moderate):
            return .medium // 推荐中等大小模型
        case (1000..<2000, .normal), (1500..<2500, .moderate):
            return .small // 建议小模型
        default:
            return .unavailable // 不建议加载任何模型
        }
    }
    
    /// 执行内存清理
    func performMemoryCleanup() {
        logger.info("Performing memory cleanup")
        
        // 清理各种缓存
        URLCache.shared.removeAllCachedResponses()
        
        // 强制垃圾回收（在可能的情况下）
        autoreleasepool {
            // 创建临时对象以触发内存回收
            _ = Array(0..<1000).map { _ in NSObject() }
        }
        
        logger.info("Memory cleanup completed")
    }
}

/// 模型大小推荐
enum ModelSizeRecommendation {
    case large      // > 3GB可用内存
    case medium     // 2-3GB可用内存
    case small      // 1-2GB可用内存
    case unavailable // < 1GB可用内存
    
    var description: String {
        switch self {
        case .large:
            return "Can load large models (e.g., Phi-3.5 7B)"
        case .medium:
            return "Recommended: medium model (e.g., Phi-3.5 Mini)"
        case .small:
            return "Recommended: lightweight model (e.g., Llama-3.2 1B)"
        case .unavailable:
            return "Insufficient memory for local model loading"
        }
    }
}
