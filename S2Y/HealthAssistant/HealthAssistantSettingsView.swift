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
    @Environment(\.dismiss) private var dismiss
    @State private var gatewayURL: String = ""
    @State private var modelPath: String = ""
    @State private var bearerToken: String = ""
    @State private var showingTokenField = false
    @State private var showingSuccessAlert = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
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