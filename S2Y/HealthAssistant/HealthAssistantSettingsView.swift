//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable closure_body_length sorted_imports trailing_comma
import Security
import SwiftUI
import AVFoundation

struct HealthAssistantSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var gatewayURL: String = ""
    @State private var modelPath: String = ""
    @State private var bearerToken: String = ""
    @State private var showingTokenField = false
    @State private var showingSuccessAlert = false
    @State private var errorMessage: String?
    @AppStorage(StorageKeys.disableTimeSensitiveNotifications) private var disableTSN = false
    @AppStorage(StorageKeys.disableScheduler) private var disableScheduler = false
    @AppStorage(StorageKeys.disableBluetooth) private var disableBluetooth = false

    // Voice & Language settings
    @AppStorage(StorageKeys.voiceEnabled) private var voiceEnabled = true
    @AppStorage(StorageKeys.voiceSpeakResponses) private var voiceSpeak = true
    @AppStorage(StorageKeys.voiceInputLanguageCode) private var voiceInputLanguageCode = ""
    @AppStorage(StorageKeys.voiceOutputLanguageCode) private var voiceOutputLanguageCode = ""
    @AppStorage(StorageKeys.voiceSpeechRate) private var voiceSpeechRate: Double = 0.5
    
    var body: some View {
        Form {
                Section {
                    Text("Configure LLM service to enable intelligent health analysis features")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Service Configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gateway URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("https://api.cloudflare.com/...", text: $gatewayURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model Path")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("v4/accounts/.../ai-gateway/...", text: $modelPath)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Voice & Language") {
                    Toggle("Enable Voice Features", isOn: $voiceEnabled)
                    Toggle("Speak Assistant Responses", isOn: $voiceSpeak)

                    Picker("Input Language", selection: $voiceInputLanguageCode) {
                        ForEach(languageOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }

                    Picker("Response Voice", selection: $voiceOutputLanguageCode) {
                        ForEach(languageOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speech Rate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $voiceSpeechRate, in: 0.2...0.7)
                    }
                    Text("Set to 'System Default' to follow the device language.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Authentication") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Bearer Token")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(bearerToken.isEmpty ? "Not Set" : "Set")
                                .foregroundColor(bearerToken.isEmpty ? .red : .green)
                        }
                        
                        Spacer()
                        
                        Button(bearerToken.isEmpty ? "Set" : "Update") {
                            showingTokenField = true
                        }
                    }
                    
                    if showingTokenField {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Please enter your Bearer Token")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Bearer Token", text: $bearerToken)
                                .textFieldStyle(.roundedBorder)
                            
                            HStack {
                                Button("Cancel") {
                                    showingTokenField = false
                                    bearerToken = loadTokenFromKeychain() ?? ""
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Save") {
                                    saveTokenToKeychain()
                                    showingTokenField = false
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(bearerToken.isEmpty)
                            }
                        }
                    }
                }

                Section("Debug Runtime Toggles") {
                    Toggle("Disable Time Sensitive Notifications", isOn: $disableTSN)
                    Toggle("Disable Scheduler", isOn: $disableScheduler)
                    Toggle("Disable Bluetooth Features", isOn: $disableBluetooth)
                    Text("Use these during on-device debugging to temporarily disable certain features.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Cache Management") {
                    Button("Clear Health Data Cache") {
                        HealthKitCache.shared.clearAll()
                        showingSuccessAlert = true
                    }
                    .foregroundColor(.red)
                }
                
                Section {
                    Text("Configuration information is saved in device Keychain to ensure data security")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
        }
        .navigationTitle("Health Assistant Settings")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save Configuration") {
                    saveConfiguration()
                }
                .disabled(gatewayURL.isEmpty)
            }
        }
        .alert("Success", isPresented: $showingSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Operation completed")
        }
        .onAppear {
            loadConfiguration()
        }
    }

    private struct LanguageOption: Identifiable {
        let id: String
        let title: String
    }

    private var languageOptions: [LanguageOption] {
        [
            LanguageOption(id: "", title: "System Default"),
            LanguageOption(id: "en-US", title: "English (US)"),
            LanguageOption(id: "zh-CN", title: "Chinese (Mandarin)"),
            LanguageOption(id: "es-ES", title: "Español (ES)"),
            LanguageOption(id: "fr-FR", title: "Français (FR)"),
            LanguageOption(id: "de-DE", title: "Deutsch (DE)"),
            LanguageOption(id: "ja-JP", title: "Japanese"),
            LanguageOption(id: "ko-KR", title: "Korean")
        ]
    }
    
    private func loadConfiguration() {
        // Load from Info.plist
        gatewayURL = Bundle.main.object(forInfoDictionaryKey: "CFWorkersAI.GatewayURL") as? String ?? ""
        modelPath = Bundle.main.object(forInfoDictionaryKey: "CFWorkersAI.ModelPath") as? String ?? ""
        
        // Load token from keychain
        if let token = loadTokenFromKeychain() {
            bearerToken = token
        }
    }
    
    private func saveConfiguration() {
        // Note: In a real app, you might want to save these to UserDefaults
        // or update the Info.plist dynamically. For now, we just validate and show success.
        
        if !gatewayURL.isEmpty {
            showingSuccessAlert = true
            errorMessage = nil
        } else {
            errorMessage = "Please fill in required fields"
        }
    }
    
    private func loadTokenFromKeychain() -> String? {
        let keychain = Keychain()
        return keychain.get(key: "gateway.token")
    }
    
    private func saveTokenToKeychain() {
        let keychain = Keychain()
        
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "gateway.token",
            kSecValueData as String: bearerToken.data(using: .utf8)!,
        ] as [String: Any]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            showingSuccessAlert = true
            errorMessage = nil
        } else {
            errorMessage = "Failed to save token"
        }
    }
}

