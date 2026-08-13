//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI

public struct WellnessSessionAuditRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let requestID: UUID
    public let deviceID: UUID
    public let purpose: WellnessSessionPurpose
    public let requestedDurationMinutes: Int
    public let comfortLevel: Int
    public let origin: WellnessSessionOrigin
    public let confirmedAt: Date
    public var endedAt: Date?
    public var stopReason: WellnessSessionStopReason?

    public init(activeSession: ActiveWellnessSession) {
        let request = activeSession.session.request
        self.id = UUID()
        self.requestID = request.id
        self.deviceID = request.deviceID
        self.purpose = request.purpose
        self.requestedDurationMinutes = request.durationMinutes
        self.comfortLevel = request.comfortLevel
        self.origin = request.origin
        self.confirmedAt = activeSession.confirmedAt
        self.endedAt = nil
        self.stopReason = nil
    }

    public mutating func finish(with stoppedSession: StoppedWellnessSession) {
        guard stoppedSession.request.id == requestID else { return }
        endedAt = stoppedSession.stoppedAt
        stopReason = stoppedSession.reason
    }
}

public struct WellnessSessionAuditLog: Codable, Sendable, Equatable {
    public private(set) var records: [WellnessSessionAuditRecord]
    public let maximumRecordCount: Int

    public init(records: [WellnessSessionAuditRecord] = [], maximumRecordCount: Int = 100) {
        self.maximumRecordCount = max(1, maximumRecordCount)
        self.records = Array(records.prefix(self.maximumRecordCount))
    }

    public mutating func begin(_ activeSession: ActiveWellnessSession) {
        records.insert(WellnessSessionAuditRecord(activeSession: activeSession), at: 0)
        records = Array(records.prefix(maximumRecordCount))
    }

    public mutating func finish(_ stoppedSession: StoppedWellnessSession) {
        guard let index = records.firstIndex(where: { $0.requestID == stoppedSession.request.id }) else {
            return
        }
        records[index].finish(with: stoppedSession)
    }
}

@MainActor
final class WellnessSessionAuditStore: ObservableObject {
    static let shared = WellnessSessionAuditStore()

    @Published private(set) var log: WellnessSessionAuditLog

    private let defaults: UserDefaults
    private let storageKey = "wellnessSessionAudit.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? decoder.decode(WellnessSessionAuditLog.self, from: data) {
            self.log = decoded
        } else {
            self.log = WellnessSessionAuditLog()
        }
    }

    func begin(_ activeSession: ActiveWellnessSession) {
        log.begin(activeSession)
        persist()
    }

    func finish(_ stoppedSession: StoppedWellnessSession) {
        log.finish(stoppedSession)
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(log) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
