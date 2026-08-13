//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziQuestionnaire
import SpeziScheduler
import SpeziViews
import SwiftUI


struct EventView: View {
    private let event: Event
    
    @Environment(S2YApplicationStandard.self) private var standard
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sharingConsentStore = HealthSharingConsentStore.shared
    
    @State private var viewState: ViewState = .idle
    @State private var pendingCloudBackupResponse: ModelsR4.QuestionnaireResponse?
    @State private var showingCloudBackupRecovery = false
    
    
    var body: some View {
        if let questionnaire = event.task.questionnaire {
            QuestionnaireView(questionnaire: questionnaire) { result in
                guard case let .completed(response) = result else { // user cancelled the task
                    dismiss()
                    return
                }
                
                do {
                    let data = try JSONEncoder().encode(response)
                    let questionnaireID = questionnaire.id?.value?.string ?? "unknown-questionnaire"
                    let snapshot = try WellbeingCheckInSnapshotBuilder.build(
                        responseData: data,
                        questionnaireIdentifier: questionnaireID
                    )
                    try WellbeingCheckInStore.shared.save(snapshot)
                    _ = try event.complete()
                    if HealthSharingConsentPolicy.permits(
                        .wellbeingCheckInCloudBackup,
                        authorization: sharingConsentStore.authorization
                    ) {
                        do {
                            try await standard.add(response: response, for: questionnaire)
                        } catch {
                            pendingCloudBackupResponse = response
                            showingCloudBackupRecovery = true
                            return
                        }
                    }
                    dismiss()
                } catch {
                    viewState = .error(AnyLocalizedError(error: error))
                }
            }
            .viewStateAlert(state: $viewState)
            .alert("Saved on this iPhone", isPresented: $showingCloudBackupRecovery) {
                Button("Retry Cloud Backup") {
                    retryPendingCloudBackup(for: questionnaire)
                }
                Button("Finish Without Cloud Backup", role: .cancel) {
                    pendingCloudBackupResponse = nil
                    dismiss()
                }
            } message: {
                Text(
                    "Your private local check-in is safe, but the optional account backup did not finish. "
                        + "You can retry now or keep only the copy on this iPhone."
                )
            }
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "Unsupported Event",
                    systemImage: "list.bullet.clipboard",
                    description: Text("This type of event is currently unsupported. Please contact the developer of this app.")
                )
                .toolbar {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    
    init(_ event: Event) {
        self.event = event
    }

    private func retryPendingCloudBackup(for questionnaire: ModelsR4.Questionnaire) {
        guard let response = pendingCloudBackupResponse else {
            return
        }
        _Concurrency.Task { await retryCloudBackup(response, for: questionnaire) }
    }

    @MainActor
    private func retryCloudBackup(
        _ response: ModelsR4.QuestionnaireResponse,
        for questionnaire: ModelsR4.Questionnaire
    ) async {
        do {
            try await standard.add(response: response, for: questionnaire)
            pendingCloudBackupResponse = nil
            dismiss()
        } catch {
            showingCloudBackupRecovery = true
        }
    }
}
