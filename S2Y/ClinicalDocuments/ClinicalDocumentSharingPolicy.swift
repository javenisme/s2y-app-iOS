//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation

enum ClinicalDocumentSharingPolicy {
    static func context(
        _ candidate: ClinicalDocumentQuestionContext?,
        for mode: AssistantAIMode,
        authorization: HealthSharingAuthorization
    ) -> ClinicalDocumentQuestionContext? {
        guard mode == .omer else {
            return candidate
        }
        return HealthSharingConsentPolicy.permits(
            .importedClinicalDocumentExcerpts,
            authorization: authorization
        ) ? candidate : nil
    }

    static func permitsConversationSync(
        using context: ClinicalDocumentQuestionContext?,
        authorization: HealthSharingAuthorization
    ) -> Bool {
        guard context != nil else {
            return true
        }
        return HealthSharingConsentPolicy.permits(
            .importedClinicalDocumentExcerpts,
            authorization: authorization
        )
    }
}
