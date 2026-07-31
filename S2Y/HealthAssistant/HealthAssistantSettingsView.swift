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
    @State private var transport: OmerTransport = .legacyAutoRAG
    @State private var shareHealthData = false
    @State private var bearerToken: String = ""
    @State private var showingTokenField = false
    @State private var showingSuccessAlert = false
    @State private var successMessage = "Changes saved"
    @State private var errorMessage: String?
    @State private var hasStoredToken = false
    @AppStorage(StorageKeys.cloudflareGatewayURL) private var storedGatewayURL = ""
    @AppStorage(StorageKeys.cloudflareModelPath) private var storedModelPath = ""
    @AppStorage(StorageKeys.omerMobileGatewayURL) private var storedMobileGatewayURL = ""
    @AppStorage(StorageKeys.omerMobileModelPath) private var storedMobileModelPath = ""
    @AppStorage(StorageKeys.omerTransport) private var storedTransport = ""
    @AppStorage(StorageKeys.shareHealthDataWithOmer) private var storedShareHealthData = false
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
                Text("Adjust how the assistant connects to Omer, speaks, and stores data on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Connection", selection: $transport) {
                    Text("Omer Mobile API").tag(OmerTransport.mobileV1)
                    Text("Legacy AutoRAG").tag(OmerTransport.legacyAutoRAG)
                }

                TextField("Omer Gateway URL", text: $gatewayURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                TextField("Route / Model Path", text: $modelPath, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...4)

                LabeledContent("Configuration Source", value: usingBundledDefaults ? "App Defaults" : "Custom on This Device")

                Button("Restore Default Service Settings") {
                    restoreDefaultServiceConfiguration()
                }
                .disabled(usingBundledDefaults)
            } header: {
                Text("Omer Service")
            } footer: {
                Text("Custom Omer endpoint values override the bundled s2y-omer/Cloudflare defaults only on this device.")
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

            if transport == .legacyAutoRAG {
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
                    Text("Legacy AutoRAG tokens are stored in Keychain. Never distribute a provider token in the App bundle.")
                }
            } else {
                Section {
                    LabeledContent("Identity", value: "S2Y Account")
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Omer uses a short-lived Firebase identity token for the signed-in S2Y account.")
                }
            }

            Section {
                Toggle("Share Relevant Health Summaries with Omer", isOn: $shareHealthData)
                Button("Clear Health Data Cache", role: .destructive) {
                    HealthKitCache.shared.clearAll()
                    presentSuccess("Health data cache cleared")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Health summaries stay on this device unless sharing is enabled. Omer receives only the currently relevant summary fields.")
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
        .onChange(of: transport) { _, newValue in
            loadEndpointDraft(for: newValue)
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
        transport = resolvedTransport
        loadEndpointDraft(for: transport)
        shareHealthData = storedShareHealthData
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

        guard let serviceURL = URL(string: normalizedGatewayURL), serviceURL.host != nil else {
            errorMessage = "Enter a valid gateway URL."
            return
        }

        guard transport != .mobileV1 || serviceURL.scheme?.lowercased() == "https" else {
            errorMessage = "Omer Mobile API requires HTTPS."
            return
        }

        if transport == .mobileV1 {
            guard serviceURL.host?.lowercased() != "api.cloudflare.com" else {
                errorMessage = "Enter the deployed s2y-omer service URL, not the Cloudflare API URL."
                return
            }
            storedMobileGatewayURL = normalizedGatewayURL == bundledGatewayURL ? "" : normalizedGatewayURL
            storedMobileModelPath = normalizedModelPath == bundledModelPath ? "" : normalizedModelPath
        } else {
            storedGatewayURL = normalizedGatewayURL == bundledGatewayURL ? "" : normalizedGatewayURL
            storedModelPath = normalizedModelPath == bundledModelPath ? "" : normalizedModelPath
        }
        storedTransport = transport == bundledTransport ? "" : transport.rawValue
        storedShareHealthData = shareHealthData
        loadEndpointDraft(for: transport)
        errorMessage = nil
        presentSuccess("Health Assistant settings saved")
    }
    
    private func loadTokenFromKeychain() -> String? {
        let serviceQuery = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.cloudflare",
            kSecAttrAccount as String: "gateway.token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as [String: Any]
        var item: CFTypeRef?
        if SecItemCopyMatching(serviceQuery as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return Keychain().get(key: "gateway.token")
    }
    
    private func saveTokenToKeychain() {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.cloudflare",
            kSecAttrAccount as String: "gateway.token",
        ] as [String: Any]

        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = bearerToken.data(using: .utf8) ?? Data()
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)

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
        storedMobileGatewayURL = ""
        storedMobileModelPath = ""
        storedTransport = ""
        transport = bundledTransport
        loadEndpointDraft(for: transport)
        errorMessage = nil
    }

    private func presentSuccess(_ message: String) {
        successMessage = message
        showingSuccessAlert = true
    }

    private var bundledGatewayURL: String {
        let key = transport == .mobileV1 ? "Omer.MobileGatewayURL" : "CFWorkersAI.GatewayURL"
        return (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var bundledModelPath: String {
        let key = transport == .mobileV1 ? "Omer.MobileModelPath" : "CFWorkersAI.ModelPath"
        return (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var resolvedGatewayURL: String {
        let storedValue = transport == .mobileV1 ? storedMobileGatewayURL : storedGatewayURL
        let override = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? bundledGatewayURL : override
    }

    private var resolvedModelPath: String {
        let storedValue = transport == .mobileV1 ? storedMobileModelPath : storedModelPath
        let override = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? bundledModelPath : override
    }

    private var bundledTransport: OmerTransport {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: "Omer.Transport") as? String
        return OmerTransport(rawValue: rawValue ?? "") ?? .legacyAutoRAG
    }

    private var resolvedTransport: OmerTransport {
        OmerTransport(rawValue: storedTransport) ?? bundledTransport
    }

    private func loadEndpointDraft(for transport: OmerTransport) {
        gatewayURL = resolvedGatewayURL
        modelPath = resolvedModelPath
        errorMessage = nil
    }

    private var usingBundledDefaults: Bool {
        let endpointUsesDefaults = transport == .mobileV1
            ? storedMobileGatewayURL.isEmpty && storedMobileModelPath.isEmpty
            : storedGatewayURL.isEmpty && storedModelPath.isEmpty
        return endpointUsesDefaults
            && storedTransport.isEmpty
    }
}
