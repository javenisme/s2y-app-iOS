//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelAvailability: Equatable, Sendable {
    case available
    case unavailable(Reason)

    enum Reason: Equatable, Sendable {
        case requiresNewerOS
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case simulatorUnsupported
        case frameworkUnavailable
    }

    var isAvailable: Bool {
        self == .available
    }

    var statusTitle: String {
        switch self {
        case .available: "Ready"
        case .unavailable(.requiresNewerOS): "Requires a newer iOS version"
        case .unavailable(.deviceNotEligible): "Not supported on this device"
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is off"
        case .unavailable(.modelNotReady): "Apple model is preparing"
        case .unavailable(.simulatorUnsupported): "Unavailable in Simulator"
        case .unavailable(.frameworkUnavailable): "Unavailable in this build"
        }
    }

    var recoveryGuidance: String {
        switch self {
        case .available:
            return "On-device requests stay on this iPhone."
        case .unavailable(.requiresNewerOS):
            return "Update iOS to use Apple's on-device model, or manually choose Omer Online."
        case .unavailable(.deviceNotEligible):
            return "This device cannot run Apple's on-device model. Manually choose Omer Online to continue."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in iPhone Settings, then return here and try again."
        case .unavailable(.modelNotReady):
            return "Keep the iPhone connected to power and Wi-Fi while Apple finishes preparing its model."
        case .unavailable(.simulatorUnsupported):
            return "Use an eligible iPhone to test Apple on-device AI, or manually choose Omer Online."
        case .unavailable(.frameworkUnavailable):
            return "Install a build that includes Apple Foundation Models, or manually choose Omer Online."
        }
    }
}

enum AppleFoundationModelError: LocalizedError {
    case unavailable(AppleFoundationModelAvailability)

    var errorDescription: String? {
        switch self {
        case .unavailable(let availability):
            return availability.recoveryGuidance
        }
    }
}

@MainActor
final class AppleFoundationModelService {
    static let shared = AppleFoundationModelService()

    #if canImport(FoundationModels)
    private var sessionStorage: AnyObject?
    #endif

    private init() {}

    var availability: AppleFoundationModelAvailability {
        #if targetEnvironment(simulator)
        return .unavailable(.simulatorUnsupported)
        #elseif canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            return .unavailable(.requiresNewerOS)
        }

        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            @unknown default:
                return .unavailable(.frameworkUnavailable)
            }
        @unknown default:
            return .unavailable(.frameworkUnavailable)
        }
        #else
        return .unavailable(.frameworkUnavailable)
        #endif
    }

    func streamResponse(
        to message: String,
        healthContext: [String: String]?,
        onSnapshot: @escaping @MainActor (String) -> Void
    ) async throws {
        let currentAvailability = availability
        guard currentAvailability.isAvailable else {
            throw AppleFoundationModelError.unavailable(currentAvailability)
        }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw AppleFoundationModelError.unavailable(.unavailable(.requiresNewerOS))
        }

        let session = foundationModelSession()
        let prompt = buildPrompt(message: message, healthContext: healthContext)
        let stream = session.streamResponse(to: prompt)

        for try await snapshot in stream {
            onSnapshot(snapshot.content)
        }
        #else
        throw AppleFoundationModelError.unavailable(.unavailable(.frameworkUnavailable))
        #endif
    }

    func resetConversation() {
        #if canImport(FoundationModels)
        sessionStorage = nil
        #endif
    }

    private func buildPrompt(message: String, healthContext: [String: String]?) -> String {
        guard let healthContext, !healthContext.isEmpty else {
            return message
        }

        let summary = healthContext
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")

        return """
        User request:
        \(message)

        Context selected on this device:
        \(summary)
        """
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private extension AppleFoundationModelService {
    func foundationModelSession() -> LanguageModelSession {
        if let session = sessionStorage as? LanguageModelSession {
            return session
        }

        let session = LanguageModelSession(instructions: """
            You are S2Y Health Assistant, a concise and supportive wellness assistant.
            Answer in the user's language. Use device health summaries only when provided.
            When imported document excerpts contain markers such as [D1], cite those markers
            and do not claim the document says anything beyond the supplied excerpts.
            Clearly distinguish observations from medical conclusions. Never diagnose,
            prescribe, or claim certainty. Encourage professional care for concerning or
            persistent symptoms, and advise emergency services for urgent warning signs.
            Do not invent measurements or say that you accessed data that was not provided.
            """)
        sessionStorage = session
        return session
    }
}
#endif
