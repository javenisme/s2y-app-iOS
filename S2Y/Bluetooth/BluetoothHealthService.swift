//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

import Foundation
import HealthKit
import OSLog
import SpeziBluetooth
import SpeziDevices
import SwiftUI

/// Service for managing Bluetooth health device connections and data collection
@MainActor
public final class BluetoothHealthService: ObservableObject {
    public static let shared = BluetoothHealthService()
    
    private let logger = Logger(subsystem: "com.s2y.app", category: "BluetoothHealth")
    
    @Published public private(set) var connectedDevices: [BluetoothHealthDevice] = []
    @Published public private(set) var isScanning = false
    @Published public private(set) var discoveredDevices: [BluetoothHealthDevice] = []
    
    private init() {}
    
    /// Start scanning for health devices
    public func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        logger.info("Starting Bluetooth health device scan")
        
        // Scanning logic will be handled by SpeziBluetooth configuration
        // This method serves as a UI state management point
    }
    
    /// Stop scanning for health devices
    public func stopScanning() {
        guard isScanning else { return }
        isScanning = false
        logger.info("Stopping Bluetooth health device scan")
    }
    
    /// Connect to a discovered health device
    public func connect(to device: BluetoothHealthDevice) async throws {
        logger.info("Attempting to connect to device: \(device.name)")
        
        // Connection logic will be implemented with specific device types
        // For now, we'll add it to connected devices
        if !connectedDevices.contains(where: { $0.id == device.id }) {
            connectedDevices.append(device)
            logger.info("Successfully connected to device: \(device.name)")
        }
    }
    
    /// Disconnect from a health device
    public func disconnect(from device: BluetoothHealthDevice) {
        logger.info("Disconnecting from device: \(device.name)")
        connectedDevices.removeAll { $0.id == device.id }
    }
    
    /// Process health data from Bluetooth devices and sync to HealthKit
    public func processHealthData(_ data: BluetoothHealthData) async throws {
        logger.info("Processing health data from Bluetooth device: \(data.deviceType.rawValue)")
        
        // Convert Bluetooth data to HealthKit samples
        let healthKitSamples = try convertToHealthKitSamples(data)
        
        // Save to HealthKit
        let healthStore = HKHealthStore()
        try await healthStore.save(healthKitSamples)
        
        logger.info("Successfully saved \(healthKitSamples.count) health samples to HealthKit")
    }
    
    private func convertToHealthKitSamples(_ data: BluetoothHealthData) throws -> [HKSample] {
        var samples: [HKSample] = []
        
        switch data.deviceType {
        case .pulseOximeter:
            samples.append(contentsOf: createPulseOximeterSamples(from: data))
        case .weightScale:
            samples.append(contentsOf: createWeightScaleSamples(from: data))
        case .bloodPressureMonitor:
            samples.append(contentsOf: createBloodPressureSamples(from: data))
        }
        
        return samples
    }
    
    private func createPulseOximeterSamples(from data: BluetoothHealthData) -> [HKSample] {
        var samples: [HKSample] = []
        
        if let oxygenSaturation = data.oxygenSaturation {
            let oxygenType = HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!
            let oxygenQuantity = HKQuantity(unit: HKUnit.percent(), doubleValue: oxygenSaturation)
            let oxygenSample = HKQuantitySample(
                type: oxygenType,
                quantity: oxygenQuantity,
                start: data.timestamp,
                end: data.timestamp
            )
            samples.append(oxygenSample)
        }
        
        if let heartRate = data.heartRate {
            let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
            let heartRateQuantity = HKQuantity(
                unit: HKUnit.count().unitDivided(by: .minute()),
                doubleValue: heartRate
            )
            let heartRateSample = HKQuantitySample(
                type: heartRateType,
                quantity: heartRateQuantity,
                start: data.timestamp,
                end: data.timestamp
            )
            samples.append(heartRateSample)
        }
        
        return samples
    }
    
    private func createWeightScaleSamples(from data: BluetoothHealthData) -> [HKSample] {
        guard let weight = data.weight else { return [] }
        
        let weightType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let weightQuantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weight)
        let weightSample = HKQuantitySample(
            type: weightType,
            quantity: weightQuantity,
            start: data.timestamp,
            end: data.timestamp
        )
        
        return [weightSample]
    }
    
    private func createBloodPressureSamples(from data: BluetoothHealthData) -> [HKSample] {
        guard let systolic = data.systolicPressure, let diastolic = data.diastolicPressure else { return [] }
        
        let systolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!
        let diastolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!
        
        let systolicQuantity = HKQuantity(unit: .millimeterOfMercury(), doubleValue: systolic)
        let diastolicQuantity = HKQuantity(unit: .millimeterOfMercury(), doubleValue: diastolic)
        
        let systolicSample = HKQuantitySample(
            type: systolicType,
            quantity: systolicQuantity,
            start: data.timestamp,
            end: data.timestamp
        )
        
        let diastolicSample = HKQuantitySample(
            type: diastolicType,
            quantity: diastolicQuantity,
            start: data.timestamp,
            end: data.timestamp
        )
        
        return [systolicSample, diastolicSample]
    }
}

/// Represents a Bluetooth health device
public struct BluetoothHealthDevice: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let deviceType: BluetoothHealthDeviceType
    public let rssi: Int
    public let isConnected: Bool
    
    public init(id: UUID = UUID(), name: String, deviceType: BluetoothHealthDeviceType, rssi: Int = 0, isConnected: Bool = false) {
        self.id = id
        self.name = name
        self.deviceType = deviceType
        self.rssi = rssi
        self.isConnected = isConnected
    }
}

/// Types of supported Bluetooth health devices
public enum BluetoothHealthDeviceType: String, CaseIterable {
    case pulseOximeter = "pulse_oximeter"
    case weightScale = "weight_scale"
    case bloodPressureMonitor = "blood_pressure_monitor"
    
    public var displayName: String {
        switch self {
        case .pulseOximeter: "Pulse Oximeter"
        case .weightScale: "Weight Scale"
        case .bloodPressureMonitor: "Blood Pressure Monitor"
        }
    }
    
    public var displayNameCN: String {
        switch self {
        case .pulseOximeter: "血氧仪"
        case .weightScale: "体重秤"
        case .bloodPressureMonitor: "血压计"
        }
    }
    
    public var icon: String {
        switch self {
        case .pulseOximeter: "heart.fill"
        case .weightScale: "scalemass.fill"
        case .bloodPressureMonitor: "heart.text.square.fill"
        }
    }
}

/// Health data collected from Bluetooth devices
public struct BluetoothHealthData {
    public let deviceType: BluetoothHealthDeviceType
    public let timestamp: Date
    
    // Pulse Oximeter data
    public let oxygenSaturation: Double?
    public let heartRate: Double?
    
    // Weight Scale data
    public let weight: Double?
    
    // Blood Pressure Monitor data
    public let systolicPressure: Double?
    public let diastolicPressure: Double?
    
    public init(
        deviceType: BluetoothHealthDeviceType,
        timestamp: Date = Date(),
        oxygenSaturation: Double? = nil,
        heartRate: Double? = nil,
        weight: Double? = nil,
        systolicPressure: Double? = nil,
        diastolicPressure: Double? = nil
    ) {
        self.deviceType = deviceType
        self.timestamp = timestamp
        self.oxygenSaturation = oxygenSaturation
        self.heartRate = heartRate
        self.weight = weight
        self.systolicPressure = systolicPressure
        self.diastolicPressure = diastolicPressure
    }
}