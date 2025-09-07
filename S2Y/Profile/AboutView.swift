//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


struct AboutView: View {
    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "v\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image("AppIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("S2Y Health Assistant")
                                .font(.headline)
                            Text(appVersionString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("A health assistant app built with Stanford Spezi.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Links") {
                if let url = URL(string: "https://spezi.stanford.edu") { Link("Project Website", destination: url) }
                if let url = URL(string: "https://github.com/StanfordBDHG/S2Y") { Link("Source Code", destination: url) }
                if let url = URL(string: "https://github.com/StanfordBDHG/S2Y/issues/new") { Link("Report a Bug", destination: url) }
            }

            Section("Legal") {
                if let url = URL(string: "https://www.stanford.edu/site/privacy/") { Link("Privacy Policy", destination: url) }
                if let url = URL(string: "https://opensource.org/license/mit/") { Link("MIT License", destination: url) }
            }
        }
        .navigationTitle("About")
    }
}


#if DEBUG
#Preview {
    AboutView()
}
#endif

