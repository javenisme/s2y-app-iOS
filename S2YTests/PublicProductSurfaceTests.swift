//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class PublicProductSurfaceTests: XCTestCase {
    func testSupportAndLegalLinksUseCurrentS2YDestinations() throws {
        let links = [
            S2YPublicLinks.website,
            S2YPublicLinks.sourceCode,
            S2YPublicLinks.reportIssue,
            S2YPublicLinks.privacyPolicy,
            S2YPublicLinks.termsOfService,
            S2YPublicLinks.consumerHealthDataPrivacy,
            S2YPublicLinks.openSourceLicense
        ]

        for link in links {
            let url = try XCTUnwrap(URL(string: link))
            XCTAssertEqual(url.scheme, "https")
            XCTAssertFalse(link.localizedCaseInsensitiveContains("StanfordBDHG"))
            XCTAssertFalse(link.localizedCaseInsensitiveContains("stanford.edu"))
        }

        XCTAssertEqual(URL(string: S2YPublicLinks.website)?.host, "www.s2y.us")
        XCTAssertEqual(URL(string: S2YPublicLinks.privacyPolicy)?.host, "www.s2y.us")
        XCTAssertEqual(URL(string: S2YPublicLinks.sourceCode)?.host, "github.com")
    }
}
