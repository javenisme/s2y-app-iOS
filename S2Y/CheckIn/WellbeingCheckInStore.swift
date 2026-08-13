//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SwiftUI

@MainActor
final class WellbeingCheckInStore: ObservableObject {
    static let shared = WellbeingCheckInStore()

    @Published private(set) var snapshots: [WellbeingCheckInSnapshot]

    private let fileManager: FileManager
    private let fileURL: URL
    private let maximumSnapshotCount: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        maximumSnapshotCount: Int = 90
    ) {
        self.fileManager = fileManager
        self.maximumSnapshotCount = max(1, maximumSnapshotCount)
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = fileURL ?? supportDirectory
            .appendingPathComponent("WellbeingCheckIns", isDirectory: true)
            .appendingPathComponent("snapshots.json")
        self.snapshots = (try? Data(contentsOf: self.fileURL))
            .flatMap { try? decoder.decode([WellbeingCheckInSnapshot].self, from: $0) }
            ?? []
    }

    func save(_ snapshot: WellbeingCheckInSnapshot) throws {
        var updated = snapshots.filter { $0.id != snapshot.id }
        updated.append(snapshot)
        updated.sort { $0.recordedAt > $1.recordedAt }
        updated = Array(updated.prefix(maximumSnapshotCount))
        try persist(updated)
        snapshots = updated
    }

    func clear() throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        snapshots = []
    }

    private func persist(_ snapshots: [WellbeingCheckInSnapshot]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(resourceValues)
        try encoder.encode(snapshots).write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
