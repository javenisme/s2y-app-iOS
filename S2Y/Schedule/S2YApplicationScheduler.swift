//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Spezi
import SpeziScheduler
import SpeziViews
import class ModelsR4.Questionnaire
import class ModelsR4.QuestionnaireResponse


@Observable
final class S2YApplicationScheduler: Module, DefaultInitializable, EnvironmentAccessible {
    @Dependency(Scheduler.self) @ObservationIgnored private var scheduler
    
    @MainActor var viewState: ViewState = .idle
    
    
    init() {}
    
    
    /// Add or update the current list of task upon app startup.
    func configure() {
        if UserDefaults.standard.bool(forKey: StorageKeys.disableScheduler) {
            return
        }
        do {
            // Daily Health Check-in Questionnaire
            try scheduler.createOrUpdateTask(
                id: "daily-health-questionnaire",
                title: "Daily Health Check-in",
                instructions: "Please complete your daily health check-in to help us provide personalized insights.",
                category: .questionnaire,
                schedule: .daily(hour: 19, minute: 0, startingAt: .today) // Evening check-in
            ) { context in
                context.questionnaire = Bundle.main.questionnaire(withName: "DailyHealthQuestionnaire")
            }
            
            // Keep existing social support questionnaire but make it weekly
            try scheduler.createOrUpdateTask(
                id: "social-support-questionnaire",
                title: "Weekly Social Support Check",
                instructions: "Please fill out the Social Support Questionnaire once a week.",
                category: .questionnaire,
                schedule: .weekly(weekday: .sunday, hour: 10, minute: 0, startingAt: .today)
            ) { context in
                context.questionnaire = Bundle.main.questionnaire(withName: "SocialSupportQuestionnaire")
            }
        } catch {
            viewState = .error(AnyLocalizedError(error: error, defaultErrorDescription: "Failed to create or update scheduled tasks."))
        }
    }
}


extension Task.Context {
    @Property(coding: .json) var questionnaire: Questionnaire?
}


extension Outcome {
    // periphery:ignore - demonstration of how to store additional context within an outcome
    @Property(coding: .json) var questionnaireResponse: QuestionnaireResponse?
}
