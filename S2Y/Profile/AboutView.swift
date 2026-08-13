//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI

enum S2YPublicLinks {
    static let website = "https://www.s2y.us"
    static let sourceCode = "https://github.com/javenisme/s2y-app-iOS"
    static let reportIssue = "https://github.com/javenisme/s2y-app-iOS/issues/new"
    static let privacyPolicy = "https://www.s2y.us/privacy-policy"
    static let privacyPolicyURL = URL(string: privacyPolicy) ?? URL(fileURLWithPath: "/")
    static let termsOfService = "https://www.s2y.us/terms-service"
    static let consumerHealthDataPrivacy = "https://www.s2y.us/consumer-health-data-privacy"
    static let openSourceLicense = "https://opensource.org/license/mit/"
}


struct AboutView: View {
    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "v\(version) (\(build))"
    }

    var body: some View {
        List {
            productSummarySection
            linksSection
            legalSection
        }
        .navigationTitle("About")
    }

    private var productSummarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image("AppIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("S2Y Health Assistant")
                            .font(.headline)
                        Text(appVersionString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(
                    "S2Y helps you understand selected Apple Health data and choose health-management actions. "
                        + "It does not provide diagnosis or treatment."
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var linksSection: some View {
        Section("Links") {
            if let url = URL(string: S2YPublicLinks.website) { Link("Project Website", destination: url) }
            if let url = URL(string: S2YPublicLinks.sourceCode) { Link("Source Code", destination: url) }
            if let url = URL(string: S2YPublicLinks.reportIssue) { Link("Report a Bug", destination: url) }
        }
    }

    private var legalSection: some View {
        Section("Legal") {
            if let url = URL(string: S2YPublicLinks.privacyPolicy) { Link("Privacy Policy", destination: url) }
            if let url = URL(string: S2YPublicLinks.termsOfService) { Link("Terms of Service", destination: url) }
            if let url = URL(string: S2YPublicLinks.consumerHealthDataPrivacy) {
                Link("Consumer Health Data Privacy", destination: url)
            }
            if let url = URL(string: S2YPublicLinks.openSourceLicense) { Link("MIT License", destination: url) }
        }
    }
}


#if DEBUG
#Preview {
    AboutView()
}
#endif
