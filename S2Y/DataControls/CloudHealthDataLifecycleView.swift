//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SwiftUI

struct CloudHealthDataLifecycleView: View {
    var body: some View {
        List {
            ForEach(CloudHealthDataLifecycle.capabilities) { capability in
                Section(capability.service.title) {
                    LabeledContent("May contain") {
                        Text(capability.storedDataDescription)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Deletion scope", value: deletionScope(capability.deletionScope))
                    LabeledContent("Where to delete", value: capability.deletionEntryPoint)
                }
            }

            Section("Before deleting an account") {
                Text(
                    "Export any local information you want to keep first. "
                        + "Deleting the Firebase account removes Firebase-owned account data, "
                        + "but does not claim to delete Apple Health or Omer conversations."
                )
                Text(
                    "Delete Omer conversations from the chat drawer. "
                        + "Then use Manage Account to review Firebase account deletion."
                )
            }
        }
        .navigationTitle("Cloud Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deletionScope(_ scope: CloudHealthDataDeletionScope) -> String {
        switch scope {
        case .account: "Whole account"
        case .individualConversation: "One conversation at a time"
        }
    }
}
