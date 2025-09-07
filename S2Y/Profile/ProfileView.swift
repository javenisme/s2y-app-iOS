//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
import SpeziAccount
import SpeziLicense


struct ProfileView: View {
    @Environment(Account.self) private var account: Account?
    @State private var showingAccountSheet = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            List {
                headerSection

                Section("Account") {
                    if let account, let details = account.details {
                        LabeledContent("User ID", value: details.userId)
                        if let name = details.name {
                            LabeledContent("Name", value: PersonNameComponentsFormatter().string(from: name))
                        }
                        Button("Manage Account") { showingAccountSheet = true }
                    } else if FeatureFlags.disableFirebase {
                        Text("Account disabled (Firebase off)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not signed in")
                            .foregroundStyle(.secondary)
                        if account != nil {
                            Button("Sign In / Create Account") { showingAccountSheet = true }
                        }
                    }
                }

                Section("App") {
                    NavigationLink("About") { AboutView() }
                    NavigationLink("Open-Source Licenses") { ContributionsList(projectLicense: .mit) }
                }

                Section("Support") {
                    if let url = URL(string: "https://github.com/StanfordBDHG/S2Y/issues/new") {
                        Link("Report a Bug", destination: url)
                    }
                    if let url = URL(string: "https://spezi.stanford.edu") {
                        Link("Help Center", destination: url)
                    }
                }

                if account != nil && !FeatureFlags.disableFirebase {
                    Section {
                        Button(role: .destructive) { showingAccountSheet = true } label: { Text("Log out") }
                    }
                }
            }
            .navigationTitle("Account")
            .sheet(isPresented: $showingAccountSheet) {
                AccountSheet(dismissAfterSignIn: false)
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(.secondary.opacity(0.2)).frame(width: 56, height: 56)
                    Image(systemName: "person.fill.questionmark")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let name = account?.details?.name, let display = PersonNameComponentsFormatter().string(from: name).nilIfEmpty {
                        Text(display).font(.headline)
                    } else {
                        Text("Welcome").font(.headline)
                    }
                    Text(account?.details?.userId ?? "Not signed in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}


#if DEBUG
#Preview {
    var details = AccountDetails()
    details.userId = "lelandstanford@stanford.edu"
    details.name = PersonNameComponents(givenName: "Leland", familyName: "Stanford")
    return ProfileView()
        .previewWith {
            AccountConfiguration(service: InMemoryAccountService(), activeDetails: details)
        }
}
#endif

