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

struct HealthAssistantSettingsView: View {
    let showsDismissButton: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var gatewayURL: String = ""
    @State private var modelPath: String = ""
    @State private var bearerToken: String = ""
    @State private var showingTokenField = false
    @State private var showingSuccessAlert = false
    @State private var successMessage = "Changes saved"
    @State private var errorMessage: String?
    @State private var hasStoredToken = false
    @AppStorage(StorageKeys.cloudflareGatewayURL) private var storedGatewayURL = ""
    @AppStorage(StorageKeys.cloudflareModelPath) private var storedModelPath = ""
    @AppStorage(StorageKeys.disableTimeSensitiveNotifications) private var disableTSN = false
    @AppStorage(StorageKeys.disableScheduler) private var disableScheduler = false
    @AppStorage(StorageKeys.disableBluetooth) private var disableBluetooth = false

    // Voice & Language settings
    @AppStorage(StorageKeys.voiceEnabled) private var voiceEnabled = true
    @AppStorage(StorageKeys.voiceSpeakResponses) private var voiceSpeak = true
    @AppStorage(StorageKeys.voiceInputLanguageCode) private var voiceInputLanguageCode = ""
    @AppStorage(StorageKeys.voiceOutputLanguageCode) private var voiceOutputLanguageCode = ""
    @AppStorage(StorageKeys.voiceSpeechRate) private var voiceSpeechRate: Double = 0.5

    init(showsDismissButton: Bool = false) {
        self.showsDismissButton = showsDismissButton
    }
    
    var body: some View {
        Form {
            Section {
                Text("Adjust how the assistant connects, speaks, and stores data on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Gateway URL", text: $gatewayURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                TextField("Model Path", text: $modelPath, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...4)

                LabeledContent("Configuration Source", value: usingBundledDefaults ? "App Defaults" : "Custom on This Device")

                Button("Restore Default Service Settings") {
                    restoreDefaultServiceConfiguration()
                }
                .disabled(usingBundledDefaults)
            } header: {
                Text("Cloud Service")
            } footer: {
                Text("Custom gateway values override the bundled defaults only on this device.")
            }

            Section {
                Toggle("Enable Voice Features", isOn: $voiceEnabled)
                Toggle("Speak Assistant Responses", isOn: $voiceSpeak)
                    .disabled(!voiceEnabled)

                Picker("Input Language", selection: $voiceInputLanguageCode) {
                    ForEach(languageOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .disabled(!voiceEnabled)

                Picker("Response Voice", selection: $voiceOutputLanguageCode) {
                    ForEach(languageOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .disabled(!voiceEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Speech Rate", value: voiceSpeechRate.formatted(.number.precision(.fractionLength(2))))
                        .font(.subheadline)
                    Slider(value: $voiceSpeechRate, in: 0.2...0.7)
                        .disabled(!voiceEnabled || !voiceSpeak)
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Use System Default to follow the device language for speech recognition and spoken responses.")
            }

            Section {
                LabeledContent("Bearer Token", value: hasStoredToken ? "Saved" : "Not Set")

                if showingTokenField {
                    SecureField("Bearer Token", text: $bearerToken)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Save Token") {
                        saveTokenToKeychain()
                    }
                    .disabled(bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Cancel", role: .cancel) {
                        cancelTokenEditing()
                    }
                } else {
                    Button(hasStoredToken ? "Update Token" : "Set Token") {
                        showingTokenField = true
                    }

                    if hasStoredToken {
                        Button("Remove Token", role: .destructive) {
                            clearTokenFromKeychain()
                        }
                    }
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("The access token is stored in Keychain and never shown in plain text after it is saved.")
            }

            Section("Data") {
                Button("Clear Health Data Cache", role: .destructive) {
                    HealthKitCache.shared.clearAll()
                    presentSuccess("Health data cache cleared")
                }
            }

            #if DEBUG
            Section {
                Toggle("Disable Time Sensitive Notifications", isOn: $disableTSN)
                Toggle("Disable Scheduler", isOn: $disableScheduler)
                Toggle("Disable Bluetooth Features", isOn: $disableBluetooth)
            } header: {
                Text("Developer Overrides")
            } footer: {
                Text("Keep test-only overrides away from normal preferences so the main settings flow stays focused.")
            }
            #endif

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Health Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveConfiguration()
                }
            }
        }
        .alert("Saved", isPresented: $showingSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage)
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
        gatewayURL = resolvedGatewayURL
        modelPath = resolvedModelPath
        hasStoredToken = loadTokenFromKeychain() != nil
        bearerToken = ""
        showingTokenField = false
    }
    
    private func saveConfiguration() {
        let normalizedGatewayURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedGatewayURL.isEmpty else {
            errorMessage = "Enter a gateway URL or restore the bundled defaults."
            return
        }

        guard URL(string: normalizedGatewayURL) != nil else {
            errorMessage = "Enter a valid gateway URL."
            return
        }

        storedGatewayURL = normalizedGatewayURL == bundledGatewayURL ? "" : normalizedGatewayURL
        storedModelPath = normalizedModelPath == bundledModelPath ? "" : normalizedModelPath
        gatewayURL = resolvedGatewayURL
        modelPath = resolvedModelPath
        errorMessage = nil
        presentSuccess("Health Assistant settings saved")
    }
    
    private func loadTokenFromKeychain() -> String? {
        let keychain = Keychain()
        return keychain.get(key: "gateway.token")
    }
    
    private func saveTokenToKeychain() {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "gateway.token",
            kSecValueData as String: bearerToken.data(using: .utf8) ?? Data(),
        ] as [String: Any]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            hasStoredToken = true
            bearerToken = ""
            showingTokenField = false
            errorMessage = nil
            presentSuccess("Access token saved to Keychain")
        } else {
            errorMessage = "Failed to save token."
        }
    }

    private func cancelTokenEditing() {
        showingTokenField = false
        bearerToken = ""
    }

    private func clearTokenFromKeychain() {
        let accountOnlyQuery = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "gateway.token",
        ] as [String: Any]
        let serviceQuery = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.cloudflare",
            kSecAttrAccount as String: "gateway.token",
        ] as [String: Any]

        SecItemDelete(accountOnlyQuery as CFDictionary)
        SecItemDelete(serviceQuery as CFDictionary)

        hasStoredToken = false
        bearerToken = ""
        showingTokenField = false
        errorMessage = nil
        presentSuccess("Access token removed")
    }

    private func restoreDefaultServiceConfiguration() {
        storedGatewayURL = ""
        storedModelPath = ""
        gatewayURL = bundledGatewayURL
        modelPath = bundledModelPath
        errorMessage = nil
    }

    private func presentSuccess(_ message: String) {
        successMessage = message
        showingSuccessAlert = true
    }

    private var bundledGatewayURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFWorkersAI.GatewayURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var bundledModelPath: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFWorkersAI.ModelPath") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var resolvedGatewayURL: String {
        let override = storedGatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? bundledGatewayURL : override
    }

    private var resolvedModelPath: String {
        let override = storedModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? bundledModelPath : override
    }

    private var usingBundledDefaults: Bool {
        storedGatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && storedModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
