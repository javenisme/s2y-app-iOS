//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class ClinicalDocumentSharingPolicyTests: XCTestCase {
    private let context = ClinicalDocumentQuestionContext(
        prompt: "[D1] bounded excerpt",
        citations: []
    )

    func testOnDeviceContextDoesNotRequireCloudSharingConsent() {
        XCTAssertEqual(
            ClinicalDocumentSharingPolicy.context(
                context,
                for: .onDevice,
                authorization: HealthSharingAuthorization()
            ),
            context
        )
    }

    func testOmerContextRequiresIndependentDocumentExcerptConsent() {
        XCTAssertNil(ClinicalDocumentSharingPolicy.context(
            context,
            for: .omer,
            authorization: HealthSharingAuthorization(grantedScopes: [.omerChatText])
        ))
        XCTAssertEqual(
            ClinicalDocumentSharingPolicy.context(
                context,
                for: .omer,
                authorization: HealthSharingAuthorization(
                    grantedScopes: [.omerChatText, .importedClinicalDocumentExcerpts]
                )
            ),
            context
        )
    }

    func testDocumentDerivedConversationCannotSyncWithoutDocumentConsent() {
        let conversationOnly = HealthSharingAuthorization(grantedScopes: [.onDeviceConversationSync])
        let both = HealthSharingAuthorization(
            grantedScopes: [.onDeviceConversationSync, .importedClinicalDocumentExcerpts]
        )

        XCTAssertFalse(ClinicalDocumentSharingPolicy.permitsConversationSync(
            using: context,
            authorization: conversationOnly
        ))
        XCTAssertTrue(ClinicalDocumentSharingPolicy.permitsConversationSync(
            using: context,
            authorization: both
        ))
    }

    func testOlderConsentReceiptCannotAuthorizeNewDocumentScope() {
        var ledger = HealthSharingConsentLedger()
        ledger.apply(
            .granted,
            scopes: [.importedClinicalDocumentExcerpts],
            policyVersion: "2026-08-12"
        )

        XCTAssertFalse(HealthSharingConsentPolicy.permits(
            .importedClinicalDocumentExcerpts,
            authorization: ledger.authorization()
        ))
    }
}
