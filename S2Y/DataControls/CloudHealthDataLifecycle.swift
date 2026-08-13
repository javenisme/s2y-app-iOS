//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

enum CloudHealthDataService: String, CaseIterable, Sendable, Identifiable {
    case firebaseAccount
    case omer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firebaseAccount: "S2Y account (Firebase)"
        case .omer: "Omer AI"
        }
    }
}

enum CloudHealthDataDeletionScope: Sendable, Equatable {
    case account
    case individualConversation
}

struct CloudHealthDataCapability: Sendable, Equatable, Identifiable {
    let service: CloudHealthDataService
    let storedDataDescription: String
    let deletionScope: CloudHealthDataDeletionScope
    let deletionEntryPoint: String

    var id: CloudHealthDataService { service }
}

enum CloudHealthDataLifecycle {
    static let capabilities = [
        CloudHealthDataCapability(
            service: .firebaseAccount,
            storedDataDescription: "Account profile, authorized questionnaire backups, and synchronized app records",
            deletionScope: .account,
            deletionEntryPoint: "Account settings"
        ),
        CloudHealthDataCapability(
            service: .omer,
            storedDataDescription: "Online conversations and explicitly synchronized on-device conversations",
            deletionScope: .individualConversation,
            deletionEntryPoint: "Chat drawer"
        )
    ]
}
