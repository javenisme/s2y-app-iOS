//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class HealthSharingCloudConfirmationTests: XCTestCase {
    func testAuthorizationResponseDecodesKnownScopesAndIgnoresFutureScope() throws {
        let data = Data(
            #"{"grantedScopes":["omerChatText","relevantHealthSummary","futureScope"]}"#.utf8
        )

        let response = try JSONDecoder().decode(OmerHealthSharingAuthorizationResponse.self, from: data)

        XCTAssertEqual(
            response.recognizedGrantedScopes,
            [.omerChatText, .relevantHealthSummary]
        )
    }

    func testStatusIsCheckingWhileRequestRuns() {
        let status = HealthSharingCloudConfirmation(
            localAuthorization: HealthSharingAuthorization(grantedScopes: [.omerChatText]),
            omerAuthorization: HealthSharingAuthorization(grantedScopes: [.omerChatText]),
            isChecking: true
        )

        XCTAssertEqual(status, .checking)
    }

    func testStatusConfirmsMatchingGrant() {
        let authorization = HealthSharingAuthorization(grantedScopes: [.omerChatText])

        let status = HealthSharingCloudConfirmation(
            localAuthorization: authorization,
            omerAuthorization: authorization,
            isChecking: false
        )

        XCTAssertEqual(status, .confirmed)
    }

    func testStatusConfirmsMatchingRevocation() {
        let authorization = HealthSharingAuthorization()

        let status = HealthSharingCloudConfirmation(
            localAuthorization: authorization,
            omerAuthorization: authorization,
            isChecking: false
        )

        XCTAssertEqual(status, .confirmed)
    }

    func testStatusDetectsMismatch() {
        let status = HealthSharingCloudConfirmation(
            localAuthorization: HealthSharingAuthorization(grantedScopes: [.omerChatText]),
            omerAuthorization: HealthSharingAuthorization(),
            isChecking: false
        )

        XCTAssertEqual(status, .pending)
    }
}
