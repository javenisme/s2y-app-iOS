//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT

import Foundation

actor OmerSessionStore {
    static let shared = OmerSessionStore()

    private let lastChatIdKeyPrefix = "omer.last-chat-id"

    private init() {}

    func lastChatId(sessionKey: String) -> String? {
        UserDefaults.standard.string(forKey: lastChatIdKey(sessionKey: sessionKey))
    }

    func saveLastChatId(_ chatId: String?, sessionKey: String) {
        let defaults = UserDefaults.standard
        let key = lastChatIdKey(sessionKey: sessionKey)

        if let chatId, !chatId.isEmpty {
            defaults.set(chatId, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func lastChatIdKey(sessionKey: String) -> String {
        "\(lastChatIdKeyPrefix).\(sessionKey)"
    }
}
