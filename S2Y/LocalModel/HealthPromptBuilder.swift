//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import OSLog

/// 健康领域提示构建器
/// 专门为Phi-3.5 Mini优化健康查询的提示工程
struct HealthPromptBuilder {
    private static let logger = Logger(subsystem: "S2Y", category: "PromptBuilder")
    
    /// 构建健康查询的完整提示
    static func buildPrompt(query: String, healthData: [String: Any]) -> String {
        logger.debug("Building health prompt for query: \(query)")
        
        let systemPrompt = buildSystemPrompt()
        let safetyGuidelines = buildSafetyGuidelines()
        let healthContext = formatHealthData(healthData)
        
        let completePrompt = """
        \(systemPrompt)
        
        \(safetyGuidelines)
        
        用户健康数据：
        \(healthContext)
        
        用户查询：\(query)
        
        请提供分析和建议：
        """
        
        logger.debug("Generated prompt length: \(completePrompt.count) characters")
        return completePrompt
    }
    
    // MARK: - Private Methods
    
    /// 构建系统提示
    private static func buildSystemPrompt() -> String {
        """
        你是一个专业的健康数据分析助手，专门分析Apple HealthKit数据。你的任务是基于用户的健康数据提供准确、有用的洞察和建议。
        
        你的分析能力：
        1. 📊 分析健康数据趋势和模式变化
        2. 💡 提供基于数据的客观洞察
        3. 🎯 给出实用的健康改善建议
        4. ⚠️ 识别需要关注的健康指标异常
        
        回复要求：
        - 使用清晰易懂的中文回复
        - 结构化组织信息（数据分析→洞察→建议）
        - 保持专业但友好的语调
        - 提供具体可行的健康建议
        - 使用适当的emoji提升可读性
        """
    }
    
    /// 构建安全指导原则
    private static func buildSafetyGuidelines() -> String {
        """
        🏥 医疗安全声明：
        • 本分析基于您的健康数据，仅供健康管理参考
        • 不能替代专业医疗诊断或治疗建议
        • 如有严重健康问题或急症，请立即就医
        • 不提供药物推荐或疾病诊断结论
        • 建议定期咨询医疗专业人士
        """
    }
    
    /// 格式化健康数据
    private static func formatHealthData(_ data: [String: Any]) -> String {
        guard !data.isEmpty else {
            return "📱 当前无可用健康数据，建议开启HealthKit权限获取更准确的分析。"
        }
        
        var formatted: [String] = []
        
        // 按健康重要性排序数据
        let priorityOrder = [
            "steps", "heartRate", "sleepAnalysis", "activeEnergyBurned",
            "heartRateVariability", "vo2Max", "walkingHeartRateAverage",
            "bloodPressure", "bodyMass", "respiratoryRate", "oxygenSaturation"
        ]
        
        // 添加优先级高的健康数据
        for key in priorityOrder {
            if let value = data[key] {
                let displayName = getHealthMetricDisplayName(key)
                let emoji = getHealthMetricEmoji(key)
                let formattedValue = formatHealthValue(value, for: key)
                formatted.append("\(emoji) \(displayName): \(formattedValue)")
            }
        }
        
        // 添加其他健康数据
        for (key, value) in data {
            if !priorityOrder.contains(key) {
                let displayName = getHealthMetricDisplayName(key)
                let emoji = getHealthMetricEmoji(key)
                let formattedValue = formatHealthValue(value, for: key)
                formatted.append("\(emoji) \(displayName): \(formattedValue)")
            }
        }
        
        return formatted.isEmpty ? 
            "📱 当前无可用健康数据" : 
            formatted.joined(separator: "\n")
    }
    
    /// 获取健康指标的显示名称
    private static func getHealthMetricDisplayName(_ key: String) -> String {
        let displayNames: [String: String] = [
            "steps": "每日步数",
            "heartRate": "心率",
            "sleepAnalysis": "睡眠分析",
            "activeEnergyBurned": "活动能量消耗",
            "heartRateVariability": "心率变异性",
            "vo2Max": "最大摄氧量",
            "walkingHeartRateAverage": "步行平均心率",
            "bloodPressure": "血压",
            "bodyMass": "体重",
            "respiratoryRate": "呼吸频率",
            "oxygenSaturation": "血氧饱和度",
            "bodyTemperature": "体温",
            "restingHeartRate": "静息心率",
            "walkingSpeed": "步行速度",
            "workoutType": "运动类型"
        ]
        return displayNames[key] ?? key.camelCaseToReadable()
    }
    
    /// 获取健康指标的emoji
    private static func getHealthMetricEmoji(_ key: String) -> String {
        let emojis: [String: String] = [
            "steps": "🚶",
            "heartRate": "💓",
            "sleepAnalysis": "😴",
            "activeEnergyBurned": "🔥",
            "heartRateVariability": "📈",
            "vo2Max": "🫁",
            "walkingHeartRateAverage": "🚶💓",
            "bloodPressure": "🩸",
            "bodyMass": "⚖️",
            "respiratoryRate": "🫁",
            "oxygenSaturation": "💨",
            "bodyTemperature": "🌡️",
            "restingHeartRate": "😌💓",
            "walkingSpeed": "🏃",
            "workoutType": "🏋️"
        ]
        return emojis[key] ?? "📊"
    }
    
    /// 格式化健康数值
    private static func formatHealthValue(_ value: Any, for key: String) -> String {
        switch value {
        case let number as NSNumber:
            return formatNumericValue(number.doubleValue, for: key)
        case let string as String:
            return string
        case let array as [Any]:
            return formatArrayValue(array, for: key)
        case let dict as [String: Any]:
            return formatDictionaryValue(dict, for: key)
        default:
            return "\(value)"
        }
    }
    
    /// 格式化数值型健康数据
    private static func formatNumericValue(_ value: Double, for key: String) -> String {
        let units: [String: String] = [
            "steps": "步",
            "heartRate": "次/分钟",
            "activeEnergyBurned": "千卡",
            "vo2Max": "ml/kg/min",
            "bodyMass": "公斤",
            "walkingHeartRateAverage": "次/分钟",
            "respiratoryRate": "次/分钟",
            "oxygenSaturation": "%",
            "bodyTemperature": "°C",
            "walkingSpeed": "km/h"
        ]
        
        let unit = units[key] ?? ""
        
        // 整数显示
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))\(unit)"
        } else {
            // 小数显示，根据数值大小决定精度
            if value < 10 {
                return String(format: "%.2f\(unit)", value)
            } else {
                return String(format: "%.1f\(unit)", value)
            }
        }
    }
    
    /// 格式化数组型健康数据
    private static func formatArrayValue(_ array: [Any], for key: String) -> String {
        if array.isEmpty {
            return "暂无数据"
        }
        
        switch key {
        case "sleepAnalysis":
            return "包含 \(array.count) 条睡眠记录"
        default:
            return "包含 \(array.count) 条记录"
        }
    }
    
    /// 格式化字典型健康数据
    private static func formatDictionaryValue(_ dict: [String: Any], for key: String) -> String {
        switch key {
        case "bloodPressure":
            if let systolic = dict["systolic"] as? Double,
               let diastolic = dict["diastolic"] as? Double {
                return "\(Int(systolic))/\(Int(diastolic)) mmHg"
            }
            return "血压数据"
        default:
            return "结构化数据 (\(dict.keys.count) 项)"
        }
    }
}

// MARK: - String Extensions

private extension String {
    /// 将驼峰命名转换为可读字符串
    func camelCaseToReadable() -> String {
        self.unicodeScalars.reduce("") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar) {
                return result + " " + String(scalar)
            }
            return result + String(scalar)
        }.trimmingCharacters(in: .whitespaces).capitalized
    }
}