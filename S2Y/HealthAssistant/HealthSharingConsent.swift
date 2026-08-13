//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI

public enum HealthSharingScope: String, Codable, Sendable, CaseIterable, Hashable {
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

public struct HealthSharingConsentFailure: LocalizedError, Sendable, Equatable {
    public let missingScopes: Set<HealthSharingScope>

    public var errorDescription: String? {
        "Review Health Assistant privacy settings before sharing: "
            + missingScopes.map(\.displayName).sorted().joined(separator: ", ")
            + "."
    }
}

private extension HealthSharingScope {
    var displayName: String {
        switch self {
        case .omerChatText: "Omer chat text"
        case .relevantHealthSummary: "relevant Health summary"
        case .onDeviceConversationSync: "on-device conversation sync"
        }
    }
}

/// Default-deny policy for every payload that can leave the iPhone.
public enum HealthSharingConsentPolicy {
    public static let currentVersion = "2026-08-12"

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

    public static func require(
        _ scopes: Set<HealthSharingScope>,
        authorization: HealthSharingAuthorization
    ) throws {
        if case let .denied(missingScopes) = decision(
            requestedScopes: scopes,
            authorization: authorization
        ) {
            throw HealthSharingConsentFailure(missingScopes: missingScopes)
        }
    }
}

public enum HealthSharingConsentChange: String, Codable, Sendable, Equatable {
    case granted
    case revoked
}

public struct HealthSharingConsentReceipt: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let policyVersion: String
    public let change: HealthSharingConsentChange
    public let changedScopes: Set<HealthSharingScope>
    public let resultingAuthorization: HealthSharingAuthorization
    public let recordedAt: Date
}

public struct HealthSharingConsentLedger: Codable, Sendable, Equatable {
    public private(set) var receipts: [HealthSharingConsentReceipt]
    public let maximumReceiptCount: Int

    public init(receipts: [HealthSharingConsentReceipt] = [], maximumReceiptCount: Int = 20) {
        self.maximumReceiptCount = max(1, maximumReceiptCount)
        self.receipts = Array(receipts.prefix(self.maximumReceiptCount))
    }

    public func authorization(policyVersion: String = HealthSharingConsentPolicy.currentVersion) -> HealthSharingAuthorization {
        guard let latest = receipts.first, latest.policyVersion == policyVersion else {
            return HealthSharingAuthorization()
        }
        return latest.resultingAuthorization
    }

    @discardableResult
    public mutating func apply(
        _ change: HealthSharingConsentChange,
        scopes: Set<HealthSharingScope>,
        policyVersion: String = HealthSharingConsentPolicy.currentVersion,
        at date: Date = .now
    ) -> HealthSharingConsentReceipt {
        var resulting = authorization(policyVersion: policyVersion)
        switch change {
        case .granted:
            resulting.grantedScopes.formUnion(scopes)
        case .revoked:
            resulting.grantedScopes.subtract(scopes)
        }
        let receipt = HealthSharingConsentReceipt(
            id: UUID(),
            policyVersion: policyVersion,
            change: change,
            changedScopes: scopes,
            resultingAuthorization: resulting,
            recordedAt: date
        )
        receipts.insert(receipt, at: 0)
        receipts = Array(receipts.prefix(maximumReceiptCount))
        return receipt
    }
}

@MainActor
final class HealthSharingConsentStore: ObservableObject {
    static let shared = HealthSharingConsentStore()

    @Published private(set) var ledger: HealthSharingConsentLedger

    private let defaults: UserDefaults
    private let storageKey = "healthSharingConsent.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? decoder.decode(HealthSharingConsentLedger.self, from: data) {
            self.ledger = decoded
        } else {
            self.ledger = HealthSharingConsentLedger()
        }
    }

    var authorization: HealthSharingAuthorization {
        ledger.authorization()
    }

    func set(_ scope: HealthSharingScope, granted: Bool, at date: Date = .now) {
        ledger.apply(granted ? .granted : .revoked, scopes: [scope], at: date)
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(ledger) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
