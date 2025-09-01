//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//


/// Constants shared across the Spezi Teamplate Application to access storage information including the `AppStorage` and `SceneStorage`
enum StorageKeys {
    // MARK: - Onboarding
    /// A `Bool` flag indicating of the onboarding was completed.
    static let onboardingFlowComplete = "onboardingFlow.complete"
    
    // MARK: - Home
    /// The currently selected home tab.
    static let homeTabSelection = "home.tabselection"
    /// The TabView customization on iPadOS
    static let tabViewCustomization = "home.tab-view-customization"

    // MARK: - Debug Toggles (Runtime)
    /// Disable Time Sensitive Notifications usage at runtime
    static let disableTimeSensitiveNotifications = "debug.disable-time-sensitive-notifications"
    /// Disable Scheduler module configuration and UI at runtime
    static let disableScheduler = "debug.disable-scheduler"
    /// Disable Bluetooth features at runtime
    static let disableBluetooth = "debug.disable-bluetooth"

    // MARK: - Voice & Language
    /// Enable or disable voice features globally
    static let voiceEnabled = "voice.enabled"
    /// Speak assistant responses using TTS
    static let voiceSpeakResponses = "voice.speak-responses"
    /// Preferred input language code for speech recognition (e.g., en-US). Empty = system
    static let voiceInputLanguageCode = "voice.input-language"
    /// Preferred output language code for speech synthesis (e.g., en-US). Empty = system
    static let voiceOutputLanguageCode = "voice.output-language"
    /// Speech rate for TTS (0.0 - 1.0)
    static let voiceSpeechRate = "voice.speech-rate"
}
