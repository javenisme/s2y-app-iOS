// Compile this full MLX integration only when MLX is available
#if canImport(MLX)
//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import OSLog

/// EnhancedLLMProvider扩展 - 本地模型集成
extension EnhancedLLMProvider {
    
    // MARK: - 本地模型属性
    
    private var localModelManager: LocalHealthModelManager {
        LocalHealthModelManager.shared
    }
    
    private var healthKitService: HealthKitService? {
        // 假设HealthKitService存在于应用中
        // 这里需要根据实际项目结构调整
        HealthKitService.shared
    }
    
    // MARK: - 公共接口
    
    /// 智能消息处理 - 自动选择最佳提供者
    public func sendMessageIntelligent(
        _ message: String,
        preferLocal: Bool = false
    ) async -> String {
        logger.info("Processing message with intelligent routing")
        
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
    
    /// 强制使用本地模型处理
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
        logger.info("Preloading local health model")
        await localModelManager.loadModelIfNeeded()
    }
    
    // MARK: - 私有实现
    
    /// 本地模型处理流程
    private func processWithLocalModel(
        _ message: String,
        includeHealthData: Bool = true
    ) async -> String {
        logger.info("Processing with local health model")
        
        do {
            // 预加载模型
            await localModelManager.loadModelIfNeeded()
            
            // 获取相关健康数据
            let healthData = includeHealthData ? await getRelevantHealthData(for: message) : [:]
            
            // 使用本地模型生成响应
            let response = try await localModelManager.generateHealthResponse(
                for: message,
                with: healthData
            )
            
            // 添加到对话上下文
            addToContext(user: message, assistant: response)
            
            logger.info("Successfully generated local model response")
            return response
            
        } catch {
            logger.error("Local model processing failed: \(error.localizedDescription)")
            
            // 降级到健康智能引擎
            return await fallbackToHealthIntelligence(message)
        }
    }
    
    /// 云端模型处理流程
    private func processWithCloudModel(_ message: String) async -> String {
        logger.info("Processing with cloud model")
        
        do {
            let response = try await sendMessage(message)
            return response.content
        } catch {
            logger.error("Cloud model processing failed: \(error.localizedDescription)")
            
            // 降级到本地模型
            return await processWithLocalModel(message)
        }
    }
    
    /// 决定是否使用本地模型
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
            logger.info("Using local model due to network unavailability")
            return true
        }
        
        // 隐私敏感查询
        if isPrivacySensitiveQuery(query) {
            logger.info("Using local model for privacy-sensitive query")
            return true
        }
        
        // 健康相关查询且本地模型可用
        if isHealthRelatedQuery(query) && isLocalModelAvailable {
            logger.info("Using local model for health-related query")
            return true
        }
        
        // 检查用户设置
        if UserDefaults.standard.bool(forKey: "PreferLocalModel") {
            return true
        }
        
        return false
    }
    
    /// 获取查询相关的健康数据
    private func getRelevantHealthData(for query: String) async -> [String: Any] {
        guard let healthKitService = healthKitService else {
            logger.warning("HealthKitService not available")
            return [:]
        }
        
        let relevantMetrics = identifyRelevantMetrics(from: query)
        var healthData: [String: Any] = [:]
        
        logger.debug("Identified relevant metrics: \(relevantMetrics)")
        
        for metric in relevantMetrics {
            do {
                let data = try await healthKitService.getRecentData(for: metric)
                healthData[metric] = data
            } catch {
                logger.warning("Failed to fetch \(metric): \(error.localizedDescription)")
            }
        }
        
        return healthData
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
            metrics.append("heartRateVariability")
            metrics.append("restingHeartRate")
            metrics.append("walkingHeartRateAverage")
        }
        
        // 睡眠相关
        if lowercaseQuery.contains("睡眠") || lowercaseQuery.contains("休息") ||
           lowercaseQuery.contains("失眠") || lowercaseQuery.contains("睡觉") {
            metrics.append("sleepAnalysis")
        }
        
        // 体重和身体组成
        if lowercaseQuery.contains("体重") || lowercaseQuery.contains("体质") ||
           lowercaseQuery.contains("BMI") || lowercaseQuery.contains("身体") {
            metrics.append("bodyMass")
        }
        
        // 血压相关
        if lowercaseQuery.contains("血压") || lowercaseQuery.contains("高血压") {
            metrics.append("bloodPressure")
        }
        
        // 血氧相关
        if lowercaseQuery.contains("血氧") || lowercaseQuery.contains("氧气") ||
           lowercaseQuery.contains("呼吸") {
            metrics.append("oxygenSaturation")
            metrics.append("respiratoryRate")
        }
        
        // 体温相关
        if lowercaseQuery.contains("体温") || lowercaseQuery.contains("发烧") ||
           lowercaseQuery.contains("温度") {
            metrics.append("bodyTemperature")
        }
        
        // 运动能力相关
        if lowercaseQuery.contains("VO2") || lowercaseQuery.contains("最大摄氧量") ||
           lowercaseQuery.contains("体能") || lowercaseQuery.contains("耐力") {
            metrics.append("vo2Max")
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
    
    /// 降级到健康智能引擎
    private func fallbackToHealthIntelligence(_ query: String) async -> String {
        logger.info("Falling back to health intelligence engine")
        
        do {
            // 尝试使用健康智能引擎
            let healthEngine = HealthIntelligenceEngine()
            let response = try await healthEngine.generateInsight(for: query)
            
            // 添加到对话上下文
            addToContext(user: query, assistant: response)
            
            return response
        } catch {
            logger.error("Health intelligence engine failed: \(error.localizedDescription)")
            
            // 最终降级到静态健康指导
            return generateStaticHealthGuidance(for: query)
        }
    }
    
    /// 生成静态健康指导
    private func generateStaticHealthGuidance(for query: String) -> String {
        logger.info("Generating static health guidance")
        
        let templates: [String: String] = [
            "步数": """
                🚶‍♀️ **关于步数的健康建议**
                
                • 建议每天至少走8000-10000步
                • 增加日常活动：选择楼梯而非电梯
                • 定期短途散步有助于身心健康
                • 循序渐进增加步数目标
                
                💡 *小贴士：分次完成比一次性完成更容易坚持*
                """,
            
            "心率": """
                💓 **关于心率的健康知识**
                
                • 正常成年人静息心率：60-100次/分钟
                • 运动时心率会自然升高
                • 规律运动有助于降低静息心率
                • 异常心率变化请咨询医生
                
                ⚠️ *如有胸痛、气短等症状，请及时就医*
                """,
                
            "睡眠": """
                😴 **关于睡眠的健康建议**
                
                • 成年人建议每天7-9小时睡眠
                • 保持规律的作息时间
                • 睡前避免使用电子设备
                • 创造安静、黑暗的睡眠环境
                
                🌙 *良好的睡眠是健康的基础*
                """,
                
            "运动": """
                🏃‍♀️ **关于运动的健康指导**
                
                • 每周至少150分钟中等强度运动
                • 结合有氧运动和力量训练
                • 选择自己喜欢的运动方式
                • 运动前做好热身准备
                
                💪 *坚持运动，收获健康*
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
            🌟 **健康生活建议**
            
            感谢您关注健康！由于当前网络不可用或AI模型暂不可用，这里为您提供一般性健康建议：
            
            • 🚶‍♀️ 保持规律的体育活动
            • 🥗 维持均衡营养的饮食
            • 😴 确保充足优质的睡眠
            • 💧 保持适当的水分摄入
            • 🧘‍♀️ 管理压力和情绪健康
            
            ⚠️ **重要提醒**：本建议仅供参考，不能替代专业医疗建议。如有健康疑虑，请咨询医疗专业人士。
            
            🔄 网络恢复后，我们将为您提供更详细的个性化健康分析。
            """
    }
    
    /// 添加到对话上下文
    private func addToContext(user: String, assistant: String) {
        let userMessage = ContextMessage(role: .user, content: user)
        let assistantMessage = ContextMessage(role: .assistant, content: assistant)
        
        contextManager.addMessage(userMessage)
        contextManager.addMessage(assistantMessage)
    }
}

// MARK: - 本地模型配置扩展

extension EnhancedLLMProvider {
    
    /// 获取本地模型状态信息
    func getLocalModelStatus() -> LocalModelStatus {
        return LocalModelStatus(
            isLoaded: localModelManager.isModelLoaded,
            status: localModelManager.modelStatus,
            loadingProgress: localModelManager.loadingProgress,
            lastError: localModelManager.lastError
        )
    }
    
    /// 卸载本地模型（释放内存）
    public func unloadLocalModel() {
        logger.info("Unloading local model via EnhancedLLMProvider")
        localModelManager.unloadModel()
    }
}

// MARK: - 状态数据结构

struct LocalModelStatus {
    let isLoaded: Bool
    let status: LocalHealthModelManager.ModelStatus
    let loadingProgress: Double
    let lastError: LocalizedError?
    
    var statusDescription: String {
        switch status {
        case .loaded:
            return "本地AI已就绪"
        case .loading:
            return "本地AI加载中..."
        case .error(let message):
            return "本地AI错误: \(message)"
        case .notLoaded:
            return "本地AI未加载"
        }
    }
}

#endif