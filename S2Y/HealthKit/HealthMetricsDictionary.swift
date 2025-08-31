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
        case body = "body"
        case sleep = "sleep"
        case nutrition = "nutrition"
        case mindfulness = "mindfulness"
        
        public var displayName: String {
            switch self {
            case .activity: return "Activity"
            case .vitals: return "Vitals"
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
        case .heartRateAverage, .restingHeartRate:
            return String(format: "%.0f %@", value, unit)
        case .activeEnergy:
            return String(format: "%.0f %@", value, unit)
        case .bodyMass:
            return String(format: "%.1f %@", value, unit)
        case .sleepDurationHours:
            return String(format: "%.1f %@", value, unit)
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
        default: return nil
        }
    }
}