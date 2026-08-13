//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

enum CrossDeviceSyncMerge {
    static func records<Payload: Codable & Equatable & Sendable>(
        local: [CrossDeviceSyncRecord<Payload>],
        remote: [CrossDeviceSyncRecord<Payload>]
    ) -> [CrossDeviceSyncRecord<Payload>] {
        Dictionary(grouping: local + remote, by: \.id)
            .compactMap { _, duplicates in
                duplicates.max(by: losesConflict)
            }
            .sorted { $0.id < $1.id }
    }

    private static func losesConflict<Payload: Codable & Equatable & Sendable>(
        _ lhs: CrossDeviceSyncRecord<Payload>,
        _ rhs: CrossDeviceSyncRecord<Payload>
    ) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt < rhs.modifiedAt
        }
        if lhs.modifiedBy != rhs.modifiedBy {
            return lhs.modifiedBy < rhs.modifiedBy
        }
        if lhs.isDeletion != rhs.isDeletion {
            return !lhs.isDeletion
        }
        return canonicalPayload(lhs.payload) < canonicalPayload(rhs.payload)
    }

    private static func canonicalPayload<Payload: Codable & Equatable & Sendable>(_ payload: Payload?) -> String {
        guard let payload else {
            return "~deleted"
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return (try? encoder.encode(payload).base64EncodedString()) ?? ""
    }
}
