import Foundation
import SwiftUI

extension HealthAssistantView {
    @MainActor
    final class LocalModelBridge: ObservableObject {
        @Published private(set) var isReady = false
        @Published private(set) var lastError: Error?
        
        private let orchestrator = LLMOrchestrator.shared
        
        func prepare() async {
            await orchestrator.prepareLocalModelIfNeeded()
            await MainActor.run {
                self.isReady = orchestrator.isLocalLoaded
                self.lastError = orchestrator.lastError
            }
        }
        
        func unload() async {
            await orchestrator.unloadLocalModel()
            await MainActor.run { self.isReady = false }
        }
        
        func send(_ userText: String, includeContext: Bool = true) async -> String {
            do {
                let reply = try await orchestrator.complete(message: userText, includeContext: includeContext)
                return reply.content
            } catch {
                await MainActor.run { self.lastError = error }
                return "抱歉，目前无法完成生成。请稍后再试。"
            }
        }
    }
    
    // Optional helper for building prompts using existing builder
    static func buildPrompt(_ userText: String, healthData: [String: Any] = [:]) -> String {
        HealthPromptBuilder.buildPrompt(query: userText, healthData: healthData)
    }
}
