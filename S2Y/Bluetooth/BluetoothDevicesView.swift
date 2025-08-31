//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT

// swiftlint:disable closure_body_length

import SwiftUI

/// View for managing Bluetooth health device connections
struct BluetoothDevicesView: View {
    @StateObject private var bluetoothService = BluetoothHealthService.shared
    @State private var showingDeviceDetails = false
    @State private var selectedDevice: BluetoothHealthDevice?
    
    var body: some View {
        NavigationView {
            List {
                scanningSection
                connectedDevicesSectionIfNeeded
                discoveredDevicesSectionIfNeeded
                supportedDevicesSection
            }
            .navigationTitle("Bluetooth Devices")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    scanButton
                }
            }
            .sheet(item: $selectedDevice) { device in
                BluetoothDeviceDetailView(device: device)
            }
        }
    }
    
    @ViewBuilder
    private var connectedDevicesSectionIfNeeded: some View {
        if !bluetoothService.connectedDevices.isEmpty {
            connectedDevicesSection
        }
    }
    
    @ViewBuilder
    private var discoveredDevicesSectionIfNeeded: some View {
        if !bluetoothService.discoveredDevices.isEmpty {
            discoveredDevicesSection
        }
    }
    
    @ViewBuilder
    private var scanningSection: some View {
        Section {
            if bluetoothService.isScanning {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Scanning for health devices...")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    Text("Tap scan to find nearby health devices")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Device Discovery")
        }
    }
    
    @ViewBuilder
    private var connectedDevicesSection: some View {
        Section("Connected Devices") {
            ForEach(bluetoothService.connectedDevices) { device in
                BluetoothDeviceRow(
                    device: device,
                    isConnected: true,
                    action: .disconnect
                ) {
                    bluetoothService.disconnect(from: device)
                }
                .onTapGesture {
                    selectedDevice = device
                    showingDeviceDetails = true
                }
            }
        }
    }
    
    @ViewBuilder
    private var discoveredDevicesSection: some View {
        Section("Available Devices") {
            ForEach(bluetoothService.discoveredDevices) { device in
                BluetoothDeviceRow(
                    device: device,
                    isConnected: false,
                    action: .connect
                ) {
                    Task {
                        do {
                            try await bluetoothService.connect(to: device)
                        } catch {
                            // Handle connection error
                            print("Failed to connect to device: \(error)")
                        }
                    }
                }
                .onTapGesture {
                    selectedDevice = device
                    showingDeviceDetails = true
                }
            }
        }
    }
    
    @ViewBuilder
    private var supportedDevicesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Supported Health Devices")
                    .font(.headline)
                
                ForEach(BluetoothHealthDeviceType.allCases, id: \.self) { deviceType in
                    HStack {
                        Image(systemName: deviceType.icon)
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deviceType.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(deviceType.displayNameCN)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Compatibility")
        } footer: {
            Text("These devices can automatically sync health data to HealthKit when connected.")
                .font(.caption)
        }
    }
    
    @ViewBuilder
    private var scanButton: some View {
        Button {
            if bluetoothService.isScanning {
                bluetoothService.stopScanning()
            } else {
                bluetoothService.startScanning()
            }
        } label: {
            if bluetoothService.isScanning {
                Text("Stop")
            } else {
                Text("Scan")
            }
        }
    }
}

/// Row view for displaying Bluetooth device information
struct BluetoothDeviceRow: View {
    let device: BluetoothHealthDevice
    let isConnected: Bool
    let action: DeviceAction
    let onAction: () -> Void
    
    enum DeviceAction {
        case connect
        case disconnect
    }
    
    var body: some View {
        HStack {
            // Device icon
            Image(systemName: device.deviceType.icon)
                .foregroundColor(isConnected ? .green : .blue)
                .frame(width: 24)
            
            // Device info
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(device.deviceType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if device.rssi != 0 {
                        Text("RSSI: \(device.rssi) dBm")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Connection status and action button
            VStack(alignment: .trailing, spacing: 4) {
                if isConnected {
                    Text("Connected")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                } else {
                    Text("Available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button {
                    onAction()
                } label: {
                    switch action {
                    case .connect:
                        Text("Connect")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    case .disconnect:
                        Text("Disconnect")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 2)
    }
}

/// Detailed view for a specific Bluetooth device
struct BluetoothDeviceDetailView: View {
    let device: BluetoothHealthDevice
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                deviceHeaderView
                deviceInfoView
                supportedMeasurementsView
                Spacer()
            }
            .padding()
            .navigationTitle("Device Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var deviceHeaderView: some View {
        HStack {
            Image(systemName: device.deviceType.icon)
                .font(.title)
                .foregroundColor(.blue)
                .frame(width: 60, height: 60)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(device.deviceType.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(device.deviceType.displayNameCN)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var deviceInfoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRow(title: "Device ID", value: device.id.uuidString)
            DetailRow(title: "Connection Status", value: device.isConnected ? "Connected" : "Disconnected")
            
            if device.rssi != 0 {
                DetailRow(title: "Signal Strength", value: "\(device.rssi) dBm")
            }
        }
    }
    
    @ViewBuilder
    private var supportedMeasurementsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported Measurements")
                .font(.headline)
            
            measurementRows(for: device.deviceType)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func measurementRows(for deviceType: BluetoothHealthDeviceType) -> some View {
        switch deviceType {
        case .pulseOximeter:
            MeasurementRow(icon: "heart.fill", name: "Heart Rate", unit: "bpm")
            MeasurementRow(icon: "lungs.fill", name: "Oxygen Saturation", unit: "%")
        case .weightScale:
            MeasurementRow(icon: "scalemass.fill", name: "Body Weight", unit: "kg")
        case .bloodPressureMonitor:
            MeasurementRow(icon: "heart.text.square.fill", name: "Blood Pressure", unit: "mmHg")
            MeasurementRow(icon: "heart.fill", name: "Heart Rate", unit: "bpm")
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct MeasurementRow: View {
    let icon: String
    let name: String
    let unit: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(name)
                .font(.subheadline)
            
            Spacer()
            
            Text(unit)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    BluetoothDevicesView()
}