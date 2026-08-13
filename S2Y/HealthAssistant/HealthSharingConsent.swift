//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

public enum HealthSharingScope: String, Codable, Sendable, CaseIterable {
    /// The question a user explicitly sends while Omer Online is selected.
    case omerChatText
    /// A short, relevant summary derived from Health data.
    case relevantHealthSummary
    /// User and assistant text produced during an on-device conversation.
    case onDeviceConversationSync
}

public struct HealthSharingAuthorization: Codable, Sendable, Equatable {
    public var grantedScopes: Set<HealthSharingScope>

    public init(grantedScopes: Set<HealthSharingScope> = []) {
        self.grantedScopes = grantedScopes
    }
}

public enum HealthSharingDecision: Sendable, Equatable {
    case allowed
    case denied(missingScopes: Set<HealthSharingScope>)
}

/// Default-deny policy for every payload that can leave the iPhone.
public enum HealthSharingConsentPolicy {
    public static func decision(
        requestedScopes: Set<HealthSharingScope>,
        authorization: HealthSharingAuthorization
    ) -> HealthSharingDecision {
        let missing = requestedScopes.subtracting(authorization.grantedScopes)
        return missing.isEmpty ? .allowed : .denied(missingScopes: missing)
    }

    public static func permits(
        _ scope: HealthSharingScope,
        authorization: HealthSharingAuthorization
    ) -> Bool {
        decision(requestedScopes: [scope], authorization: authorization) == .allowed
    }
}
