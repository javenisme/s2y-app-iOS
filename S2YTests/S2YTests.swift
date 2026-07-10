//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

@testable import S2Y
import Testing


@Suite("S2Y Tests")
struct S2YTests {
    @Test("Contacts count")
    @MainActor
    func contactsCount() {
        #expect(Contacts(presentingAccount: .constant(true)).contacts.count == 1)
    }
}
