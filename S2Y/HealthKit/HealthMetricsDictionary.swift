//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

import Foundation
import HealthKit

/// Comprehensive dictionary of health metrics with metadata and localization support
public struct HealthMetricsDictionary {
    
    /// Metadata for a health metric
    public struct MetricInfo: Sendable, Codable {
        public let identifier: String
        public let displayName: String
        public let displayNameCN: String
        public let unit: String
        public let unitCN: String
        public let description: String
        public let descriptionCN: String
        public let category: MetricCategory
        public let normalRange: Range?
        public let isHigherBetter: Bool
        
        public struct Range: Sendable, Codable {
            public let min: Double
            public let max: Double
            public let unit: String
            
            public init(min: Double, max: Double, unit: String) {
                self.min = min
                self.max = max
                self.unit = unit
            }
        }
        
        public init(
            identifier: String,
            displayName: String,
            displayNameCN: String,
            unit: String,
            unitCN: String,
            description: String,
            descriptionCN: String,
            category: MetricCategory,
            normalRange: Range? = nil,
            isHigherBetter: Bool = true
        ) {
            self.identifier = identifier
            self.displayName = displayName
            self.displayNameCN = displayNameCN
            self.unit = unit
            self.unitCN = unitCN
            self.description = description
            self.descriptionCN = descriptionCN
            self.category = category
            self.normalRange = normalRange
            self.isHigherBetter = isHigherBetter
        }
    }
    
    /// Categories for health metrics
    public enum MetricCategory: String, Sendable, Codable, CaseIterable {
        case activity = "activity"
        case vitals = "vitals"
        case cardiac = "cardiac"
        case body = "body"
        case sleep = "sleep"
        case nutrition = "nutrition"
        case mindfulness = "mindfulness"
        
        public var displayName: String {
            switch self {
            case .activity: return "Activity"
            case .vitals: return "Vitals"
            case .cardiac: return "Cardiac Health"
            case .body: return "Body Measurements"
            case .sleep: return "Sleep"
            case .nutrition: return "Nutrition"
            case .mindfulness: return "Mindfulness"
            }
        }
        
        public var displayNameCN: String {
            switch self {
            case .activity: return "活动"
            case .vitals: return "生命体征"
            case .cardiac: return "心脏健康"
            case .body: return "身体测量"
            case .sleep: return "睡眠"
            case .nutrition: return "营养"
            case .mindfulness: return "正念"
            }
        }
    }
    
    /// Static dictionary of all supported metrics
    public static let metrics: [HealthKitService.MetricKind: MetricInfo] = [
        .steps: MetricInfo(
            identifier: "steps",
            displayName: "Steps",
            displayNameCN: "步数",
            unit: "steps",
            unitCN: "步",
            description: "Number of steps taken throughout the day",
            descriptionCN: "一天中走的步数",
            category: .activity,
            normalRange: MetricInfo.Range(min: 8000, max: 12000, unit: "steps"),
            isHigherBetter: true
        ),
        
        .heartRateAverage: MetricInfo(
            identifier: "heartRateAverage",
            displayName: "Average Heart Rate",
            displayNameCN: "平均心率",
            unit: "bpm",
            unitCN: "次/分",
            description: "Average heart rate throughout the day",
            descriptionCN: "一天中的平均心率",
            category: .vitals,
            normalRange: MetricInfo.Range(min: 60, max: 100, unit: "bpm"),
            isHigherBetter: false
        ),
        
        .restingHeartRate: MetricInfo(
            identifier: "restingHeartRate",
            displayName: "Resting Heart Rate",
            displayNameCN: "静息心率",
            unit: "bpm",
            unitCN: "次/分",
            description: "Heart rate while at rest",
            descriptionCN: "静息时的心率",
            category: .vitals,
            normalRange: MetricInfo.Range(min: 50, max: 90, unit: "bpm"),
            isHigherBetter: false
        ),
        
        .activeEnergy: MetricInfo(
            identifier: "activeEnergy",
            displayName: "Active Energy",
            displayNameCN: "活动能量",
            unit: "kcal",
            unitCN: "千卡",
            description: "Calories burned through physical activity",
            descriptionCN: "通过体力活动消耗的卡路里",
            category: .activity,
            normalRange: MetricInfo.Range(min: 200, max: 800, unit: "kcal"),
            isHigherBetter: true
        ),
        
        .bodyMass: MetricInfo(
            identifier: "bodyMass",
            displayName: "Body Weight",
            displayNameCN: "体重",
            unit: "kg",
            unitCN: "公斤",
            description: "Current body weight",
            descriptionCN: "当前体重",
            category: .body,
            isHigherBetter: false
        ),
        
        .sleepDurationHours: MetricInfo(
            identifier: "sleepDurationHours",
            displayName: "Sleep Duration",
            displayNameCN: "睡眠时长",
            unit: "hours",
            unitCN: "小时",
            description: "Total hours of sleep per night",
            descriptionCN: "每晚的总睡眠小时数",
            category: .sleep,
            normalRange: MetricInfo.Range(min: 7, max: 9, unit: "hours"),
            isHigherBetter: true
        ),
        
        // MARK: - Advanced Cardiac Metrics
        
        .heartRateVariability: MetricInfo(
            identifier: "heartRateVariability",
            displayName: "Heart Rate Variability (HRV)",
            displayNameCN: "心率变异性",
            unit: "ms",
            unitCN: "毫秒",
            description: "Standard deviation of heart rate intervals, indicating cardiac health",
            descriptionCN: "心率间期的标准差，反映心脏健康状况",
            category: .cardiac,
            normalRange: MetricInfo.Range(min: 20, max: 50, unit: "ms"),
            isHigherBetter: true
        ),
        
        .heartRateRecovery: MetricInfo(
            identifier: "heartRateRecovery",
            displayName: "Heart Rate Recovery",
            displayNameCN: "心率恢复",
            unit: "bpm",
            unitCN: "次/分",
            description: "Heart rate decrease one minute after exercise ends",
            descriptionCN: "运动结束后一分钟内心率下降幅度",
            category: .cardiac,
            normalRange: MetricInfo.Range(min: 12, max: 25, unit: "bpm"),
            isHigherBetter: true
        ),
        
        .vo2Max: MetricInfo(
            identifier: "vo2Max",
            displayName: "VO₂ Max",
            displayNameCN: "最大摄氧量",
            unit: "ml/kg/min",
            unitCN: "毫升/公斤/分钟",
            description: "Maximum oxygen consumption during exercise",
            descriptionCN: "运动时最大氧气消耗量",
            category: .cardiac,
            normalRange: MetricInfo.Range(min: 35, max: 55, unit: "ml/kg/min"),
            isHigherBetter: true
        ),
        
        .walkingHeartRateAverage: MetricInfo(
            identifier: "walkingHeartRateAverage",
            displayName: "Walking Heart Rate",
            displayNameCN: "步行心率",
            unit: "bpm",
            unitCN: "次/分",
            description: "Average heart rate during walking activities",
            descriptionCN: "步行活动时的平均心率",
            category: .cardiac,
            normalRange: MetricInfo.Range(min: 90, max: 130, unit: "bpm"),
            isHigherBetter: false
        ),
        
        .oxygenSaturation: MetricInfo(
            identifier: "oxygenSaturation",
            displayName: "Blood Oxygen",
            displayNameCN: "血氧饱和度",
            unit: "%",
            unitCN: "%",
            description: "Percentage of oxygen in the blood",
            descriptionCN: "血液中氧气的百分比",
            category: .vitals,
            normalRange: MetricInfo.Range(min: 95, max: 100, unit: "%"),
            isHigherBetter: true
        ),
        
        // MARK: - Additional Vitals
        
        .bloodPressureSystolic: MetricInfo(
            identifier: "bloodPressureSystolic",
            displayName: "Systolic Blood Pressure",
            displayNameCN: "收缩压",
            unit: "mmHg",
            unitCN: "毫米汞柱",
            description: "Blood pressure when heart contracts",
            descriptionCN: "心脏收缩时的血压",
            category: .vitals,
            normalRange: MetricInfo.Range(min: 90, max: 120, unit: "mmHg"),
            isHigherBetter: false
        ),
        
        .bloodPressureDiastolic: MetricInfo(
            identifier: "bloodPressureDiastolic",
            displayName: "Diastolic Blood Pressure",
            displayNameCN: "舒张压",
            unit: "mmHg",
            unitCN: "毫米汞柱",
            description: "Blood pressure when heart relaxes",
            descriptionCN: "心脏舒张时的血压",
            category: .vitals,
            normalRange: MetricInfo.Range(min: 60, max: 80, unit: "mmHg"),
            isHigherBetter: false
        ),
        
        .bodyTemperature: MetricInfo(
            identifier: "bodyTemperature",
            displayName: "Body Temperature",
            displayNameCN: "体温",
            unit: "°C",
            unitCN: "摄氏度",
            description: "Core body temperature",
            descriptionCN: "核心体温",
            category: .vitals,
            normalRange: MetricInfo.Range(min: 36.1, max: 37.2, unit: "°C"),
            isHigherBetter: false
        ),
        
        .respiratoryRate: MetricInfo(
            identifier: "respiratoryRate",
            displayName: "Respiratory Rate",
            displayNameCN: "呼吸频率",
            unit: "breaths/min",
            unitCN: "次/分钟",
            description: "Number of breaths per minute",
            descriptionCN: "每分钟呼吸次数",
            category: .vitals,
            normalRange: MetricInfo.Range(min: 12, max: 20, unit: "breaths/min"),
            isHigherBetter: false
        )
    ]
    
    /// Get metric info by kind
    public static func info(for kind: HealthKitService.MetricKind) -> MetricInfo? {
        return metrics[kind]
    }
    
    /// Get all metrics in a category
    public static func metrics(in category: MetricCategory) -> [HealthKitService.MetricKind: MetricInfo] {
        return metrics.filter { $0.value.category == category }
    }
    
    /// Get localized display name
    public static func displayName(for kind: HealthKitService.MetricKind, locale: Locale = Locale.current) -> String {
        guard let info = info(for: kind) else { return kind.rawValue }
        
        if locale.identifier.hasPrefix("zh") {
            return info.displayNameCN
        } else {
            return info.displayName
        }
    }
    
    /// Get localized unit
    public static func unit(for kind: HealthKitService.MetricKind, locale: Locale = Locale.current) -> String {
        guard let info = info(for: kind) else { return "" }
        
        if locale.identifier.hasPrefix("zh") {
            return info.unitCN
        } else {
            return info.unit
        }
    }
    
    /// Get localized description
    public static func description(for kind: HealthKitService.MetricKind, locale: Locale = Locale.current) -> String {
        guard let info = info(for: kind) else { return "" }
        
        if locale.identifier.hasPrefix("zh") {
            return info.descriptionCN
        } else {
            return info.description
        }
    }
    
    /// Check if a value is within normal range
    public static func isNormalRange(value: Double, for kind: HealthKitService.MetricKind) -> Bool? {
        guard let info = info(for: kind), let range = info.normalRange else { return nil }
        return value >= range.min && value <= range.max
    }
    
    /// Get health assessment for a value
    public static func healthAssessment(value: Double, for kind: HealthKitService.MetricKind, locale: Locale = Locale.current) -> String {
        guard let info = info(for: kind), let range = info.normalRange else {
            return locale.identifier.hasPrefix("zh") ? "正常范围" : "Normal"
        }
        
        if value >= range.min && value <= range.max {
            return locale.identifier.hasPrefix("zh") ? "正常" : "Normal"
        } else if value < range.min {
            if info.isHigherBetter {
                return locale.identifier.hasPrefix("zh") ? "偏低" : "Below Normal"
            } else {
                return locale.identifier.hasPrefix("zh") ? "优秀" : "Excellent"
            }
        } else {
            if info.isHigherBetter {
                return locale.identifier.hasPrefix("zh") ? "优秀" : "Excellent"
            } else {
                return locale.identifier.hasPrefix("zh") ? "偏高" : "Above Normal"
            }
        }
    }
    
    /// Format value with appropriate unit and locale
    public static func formatValue(_ value: Double, for kind: HealthKitService.MetricKind, locale: Locale = Locale.current) -> String {
        let unit = self.unit(for: kind, locale: locale)
        
        switch kind {
        case .steps:
            return String(format: "%.0f %@", value, unit)
        case .heartRateAverage, .restingHeartRate, .walkingHeartRateAverage, .heartRateRecovery:
            return String(format: "%.0f %@", value, unit)
        case .activeEnergy:
            return String(format: "%.0f %@", value, unit)
        case .bodyMass:
            return String(format: "%.1f %@", value, unit)
        case .sleepDurationHours:
            return String(format: "%.1f %@", value, unit)
        case .heartRateVariability:
            return String(format: "%.1f %@", value, unit)
        case .vo2Max:
            return String(format: "%.1f %@", value, unit)
        case .oxygenSaturation:
            return String(format: "%.1f %@", value, unit)
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            return String(format: "%.0f %@", value, unit)
        case .bodyTemperature:
            return String(format: "%.1f %@", value, unit)
        case .respiratoryRate:
            return String(format: "%.0f %@", value, unit)
        }
    }
}

// MARK: - MetricKind Extensions

extension HealthKitService.MetricKind: RawRepresentable {
    public var rawValue: String {
        switch self {
        case .steps: "steps"
        case .heartRateAverage: "heartRateAverage"
        case .restingHeartRate: "restingHeartRate"
        case .activeEnergy: "activeEnergy"
        case .bodyMass: "bodyMass"
        case .sleepDurationHours: "sleepDurationHours"
        case .heartRateVariability: "heartRateVariability"
        case .heartRateRecovery: "heartRateRecovery"
        case .vo2Max: "vo2Max"
        case .walkingHeartRateAverage: "walkingHeartRateAverage"
        case .oxygenSaturation: "oxygenSaturation"
        case .bloodPressureSystolic: "bloodPressureSystolic"
        case .bloodPressureDiastolic: "bloodPressureDiastolic"
        case .bodyTemperature: "bodyTemperature"
        case .respiratoryRate: "respiratoryRate"
        }
    }
    
    public init?(rawValue: String) {
        switch rawValue {
        case "steps": self = .steps
        case "heartRateAverage": self = .heartRateAverage
        case "restingHeartRate": self = .restingHeartRate
        case "activeEnergy": self = .activeEnergy
        case "bodyMass": self = .bodyMass
        case "sleepDurationHours": self = .sleepDurationHours
        case "heartRateVariability": self = .heartRateVariability
        case "heartRateRecovery": self = .heartRateRecovery
        case "vo2Max": self = .vo2Max
        case "walkingHeartRateAverage": self = .walkingHeartRateAverage
        case "oxygenSaturation": self = .oxygenSaturation
        case "bloodPressureSystolic": self = .bloodPressureSystolic
        case "bloodPressureDiastolic": self = .bloodPressureDiastolic
        case "bodyTemperature": self = .bodyTemperature
        case "respiratoryRate": self = .respiratoryRate
        default: return nil
        }
    }
}