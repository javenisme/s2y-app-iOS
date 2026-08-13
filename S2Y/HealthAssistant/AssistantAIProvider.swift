//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

enum AssistantAIMode: String, CaseIterable, Identifiable, Sendable {
    case onDevice
    case omer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: "On-device"
        case .omer: "Omer Online"
        }
    }

    var systemImage: String {
        switch self {
        case .onDevice: "apple.intelligence"
        case .omer: "icloud"
        }
    }

    var usesNetwork: Bool {
        self == .omer
    }

    var dataBoundaryDescription: String {
        switch self {
        case .onDevice: "Runs on this iPhone"
        case .omer: "Uses Omer online"
        }
    }
}
