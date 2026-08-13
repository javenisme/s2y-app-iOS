//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

struct CrossDeviceDeviceIdentity: Sendable {
    let id: String

    init(defaults: UserDefaults = .standard) {
        let key = "crossDeviceSync.deviceID.v1"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            id = existing
        } else {
            let created = UUID().uuidString.lowercased()
            defaults.set(created, forKey: key)
            id = created
        }
    }
}
