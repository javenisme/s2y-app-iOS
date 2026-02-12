// Compile this simplified integration only when MLX is NOT available
#if !canImport(MLX)
//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import OSLog

/// EnhancedLLMProvider扩展 - 本地模型集成（简化可编译版本）
extension EnhancedLLMProvider {
    private var extLogger: Logger { Logger(subsystem: "com.s2y.app", category: "EnhancedLLM.Simplified") }
    
    // MARK: - 本地模型属性
    
    private var localModelManager: LocalHealthModelManager_Simplified {
        LocalHealthModelManager_Simplified.shared
    }
    
    // MARK: - 公共接口
    
    /// 智能消息处理 - 自动选择最佳提供者（简化版本）
    public func sendMessageIntelligent(
        _ message: String,
        preferLocal: Bool = false
    ) async -> String {
        extLogger.info("Processing message with intelligent routing (simplified)")
        
        // 决策逻辑：本地 vs 云端
        let shouldUseLocal = await shouldUseLocalModel(
            query: message,
            userPreference: preferLocal
        )
        
        if shouldUseLocal {
            return await processWithLocalModel(message)
        } else {
            return await processWithCloudModel(message)
        }
    }
    
    /// 强制使用本地模型处理（简化版本）
    public func sendMessageLocal(
        _ message: String,
        includeHealthData: Bool = true
    ) async -> String {
        return await processWithLocalModel(message, includeHealthData: includeHealthData)
    }
    
    /// 检查本地模型可用性
    public var isLocalModelAvailable: Bool {
        localModelManager.isModelLoaded || localModelManager.modelStatus == .loading
    }
    
    /// 预加载本地模型
    public func preloadLocalModel() async {
        extLogger.info("Preloading local health model (simplified)")
        await localModelManager.loadModelIfNeeded()
    }
    
    // MARK: - 私有实现
    
    /// 本地模型处理流程（简化版本）
    private func processWithLocalModel(
        _ message: String,
        includeHealthData: Bool = true
    ) async -> String {
        extLogger.info("Processing with local health model (simplified)")
        
        do {
            // 预加载模型
            await localModelManager.loadModelIfNeeded()
            
            // 获取相关健康数据（简化版本）
            let healthData = includeHealthData ? await getSimulatedHealthData(for: message) : [:]
            
            // 使用本地模型生成响应
            let response = try await localModelManager.generateHealthResponse(
                for: message,
                with: healthData
            )
            
            extLogger.info("Successfully generated local model response (simplified)")
            return response
            
        } catch {
            extLogger.error("Local model processing failed: \(error.localizedDescription)")
            
            // 降级到健康智能引擎或静态响应
            return await fallbackToStaticHealthGuidance(message)
        }
    }
    
    /// 云端模型处理流程（简化版本）
    private func processWithCloudModel(_ message: String) async -> String {
        extLogger.info("Processing with cloud model (simplified)")
        
        do {
            let response = try await sendMessage(message)
            return response.content
        } catch {
            extLogger.error("Cloud model processing failed: \(error.localizedDescription)")
            
            // 降级到本地模型
            return await processWithLocalModel(message)
        }
    }
    
    /// 决定是否使用本地模型（简化版本）
    private func shouldUseLocalModel(
        query: String,
        userPreference: Bool
    ) async -> Bool {
        // 用户明确偏好
        if userPreference {
            return true
        }
        
        // 网络不可用
        if !isOnline {
            extLogger.info("Using local model due to network unavailability")
            return true
        }
        
        // 隐私敏感查询
        if isPrivacySensitiveQuery(query) {
            extLogger.info("Using local model for privacy-sensitive query")
            return true
        }
        
        // 健康相关查询且本地模型可用
        if isHealthRelatedQuery(query) && isLocalModelAvailable {
            extLogger.info("Using local model for health-related query")
            return true
        }
        
        // 检查用户设置
        if UserDefaults.standard.bool(forKey: "PreferLocalModel") {
            return true
        }
        
        return false
    }
    
    /// 获取模拟的健康数据（简化版本）
    private func getSimulatedHealthData(for query: String) async -> [String: Any] {
        let relevantMetrics = identifyRelevantMetrics(from: query)
        var healthData: [String: Any] = [:]
        
        extLogger.debug("Identified relevant metrics: \(relevantMetrics)")
        
        // 生成模拟健康数据
        for metric in relevantMetrics {
            healthData[metric] = generateSimulatedData(for: metric)
        }
        
        return healthData
    }
    
    /// 生成模拟健康数据
    private func generateSimulatedData(for metric: String) -> Any {
        switch metric {
        case "steps":
            return Int.random(in: 5000...12000)
        case "heartRate":
            return Int.random(in: 60...90)
        case "sleepAnalysis":
            return ["duration": Double.random(in: 6.0...9.0), "quality": "Good"]
        case "activeEnergyBurned":
            return Int.random(in: 200...600)
        case "bodyMass":
            return Double.random(in: 60...80)
        default:
            return "Simulated data"
        }
    }
    
    /// 识别查询相关的健康指标
    private func identifyRelevantMetrics(from query: String) -> [String] {
        let lowercaseQuery = query.lowercased()
        var metrics: [String] = []
        
        // 步数和活动相关
        if lowercaseQuery.contains("步数") || lowercaseQuery.contains("步") || 
           lowercaseQuery.contains("走路") || lowercaseQuery.contains("活动") ||
           lowercaseQuery.contains("运动") {
            metrics.append("steps")
            metrics.append("activeEnergyBurned")
        }
        
        // 心率相关
        if lowercaseQuery.contains("心率") || lowercaseQuery.contains("心跳") ||
           lowercaseQuery.contains("心脏") || lowercaseQuery.contains("心血管") {
            metrics.append("heartRate")
        }
        
        // 睡眠相关
        if lowercaseQuery.contains("睡眠") || lowercaseQuery.contains("休息") ||
           lowercaseQuery.contains("失眠") || lowercaseQuery.contains("睡觉") {
            metrics.append("sleepAnalysis")
        }
        
        // 体重相关
        if lowercaseQuery.contains("体重") || lowercaseQuery.contains("体质") ||
           lowercaseQuery.contains("BMI") || lowercaseQuery.contains("身体") {
            metrics.append("bodyMass")
        }
        
        // 如果没有匹配到特定指标，返回基础指标集
        if metrics.isEmpty {
            metrics = ["steps", "heartRate", "sleepAnalysis", "activeEnergyBurned"]
        }
        
        return Array(Set(metrics)) // 去重
    }
    
    /// 判断是否为隐私敏感查询
    private func isPrivacySensitiveQuery(_ query: String) -> Bool {
        let sensitiveKeywords = [
            "个人", "隐私", "敏感", "私密", "保密",
            "症状", "疾病", "药物", "治疗", "诊断",
            "心理", "情绪", "抑郁", "焦虑"
        ]
        
        let lowercaseQuery = query.lowercased()
        return sensitiveKeywords.contains { lowercaseQuery.contains($0) }
    }
    
    /// 判断是否为健康相关查询
    private func isHealthRelatedQuery(_ query: String) -> Bool {
        let healthKeywords = [
            "健康", "身体", "医疗", "症状", "疾病",
            "步数", "心率", "睡眠", "血压", "体重",
            "运动", "锻炼", "饮食", "营养", "体检"
        ]
        
        let lowercaseQuery = query.lowercased()
        return healthKeywords.contains { lowercaseQuery.contains($0) }
    }
    
    /// 降级到静态健康指导（简化版本）
    private func fallbackToStaticHealthGuidance(_ query: String) async -> String {
        extLogger.info("Generating static health guidance (simplified)")
        
        let templates: [String: String] = [
            "步数": """
                🚶‍♀️ **Step Count Guidance**
                
                • Aim for roughly 8,000-10,000 steps/day
                • Add activity by choosing stairs over elevators
                • Short regular walks can improve overall wellness
                
                💡 *Tip: small activity blocks are easier to sustain*
                
                🤖 *Generated by local AI assistant (simplified mode)*
                """,
            
            "心率": """
                💓 **Heart Rate Guidance**
                
                • Typical resting heart rate for adults: 60-100 bpm
                • Heart rate naturally rises during exercise
                • Regular training can improve resting heart rate
                
                ⚠️ *Seek medical care for chest pain, shortness of breath, or similar symptoms*
                
                🤖 *Generated by local AI assistant (simplified mode)*
                """,
                
            "睡眠": """
                😴 **Sleep Guidance**
                
                • Adults typically benefit from 7-9 hours of sleep
                • Keep a consistent sleep/wake schedule
                • Limit screen exposure before bedtime
                
                🌙 *Good sleep is a core pillar of health*
                
                🤖 *Generated by local AI assistant (simplified mode)*
                """
        ]
        
        // 根据查询内容匹配模板
        for (keyword, template) in templates {
            if query.contains(keyword) {
                return template
            }
        }
        
        // 默认通用健康指导
        return """
            🌟 **Healthy Living Guidance**
            
            Thanks for focusing on your health. Here are general recommendations:
            
            • 🚶‍♀️ Keep regular physical activity
            • 🥗 Maintain a balanced, nutritious diet
            • 😴 Ensure enough high-quality sleep
            • 💧 Stay consistently hydrated
            • 🧘‍♀️ Manage stress and emotional wellbeing
            
            ⚠️ **Important**: This guidance is informational and does not replace professional medical advice.
            
            🤖 *Generated by local AI assistant (simplified mode)*
            """
    }
}

// MARK: - 本地模型配置扩展

extension EnhancedLLMProvider {
    
    /// 获取本地模型状态信息（简化版本）
    func getLocalModelStatus() -> LocalModelStatus_Simplified {
        return LocalModelStatus_Simplified(
            isLoaded: localModelManager.isModelLoaded,
            status: localModelManager.modelStatus,
            loadingProgress: localModelManager.loadingProgress,
            lastError: localModelManager.lastError
        )
    }
    
    /// 卸载本地模型（释放内存）
    public func unloadLocalModel() {
        extLogger.info("Unloading local model via EnhancedLLMProvider (simplified)")
        localModelManager.unloadModel()
    }
}

// MARK: - 状态数据结构（简化版本）

struct LocalModelStatus_Simplified {
    let isLoaded: Bool
    let status: LocalHealthModelManager_Simplified.ModelStatus
    let loadingProgress: Double
    let lastError: LocalizedError?
    
    public var statusDescription: String {
        switch status {
        case .loaded:
            return "Local AI ready (simplified mode)"
        case .loading:
            return "Local AI loading..."
        case .error(let message):
            return "Local AI error: \(message)"
        case .notLoaded:
            return "Local AI not loaded"
        }
    }
}

#endif
