//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

struct CrossDeviceSyncRecord<Payload: Codable & Equatable & Sendable>: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let payload: Payload?
    let modifiedAt: Date
    let modifiedBy: String

    var isDeletion: Bool { payload == nil }
}
