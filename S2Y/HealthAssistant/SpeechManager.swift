//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechManager: ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published var transcript: String = ""
    @Published private(set) var authorizationGranted: Bool = false
    @Published private(set) var micPermissionGranted: Bool = false

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private let synthesizer = AVSpeechSynthesizer()
    private var tapInstalled = false

    init() {
        Task { await requestAuthorizationsIfNeeded() }
    }

    func requestAuthorizationsIfNeeded() async {
        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationGranted = speechStatus == .authorized

        let micGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        micPermissionGranted = micGranted
    }

    func startRecording(languageCode: String?) async throws {
        guard !isRecording else { return }

        // Ensure permissions are granted; try to request once if not.
        if !authorizationGranted || !micPermissionGranted {
            await requestAuthorizationsIfNeeded()
        }
        guard authorizationGranted else {
            throw NSError(domain: "SpeechManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission not granted. Please enable it in Settings."])
        }
        guard micPermissionGranted else {
            throw NSError(domain: "SpeechManager", code: -11, userInfo: [NSLocalizedDescriptionKey: "Microphone access not granted. Please enable it in Settings."])
        }

        // Simulator may lack mic input; we'll rely on input route checks below instead of unconditionally throwing.

        // Determine locale
        let localeIdentifier = (languageCode?.isEmpty == false) ? languageCode! : Locale.autoupdatingCurrent.identifier
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw NSError(domain: "SpeechManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported language: \(localeIdentifier)"])
        }
        speechRecognizer = recognizer
        guard recognizer.isAvailable else {
            throw NSError(domain: "SpeechManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available for the selected locale. Please try again later."])
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        // Validate that we have an available input route before proceeding
        if (audioSession.availableInputs ?? []).isEmpty {
            throw NSError(domain: "SpeechManager", code: -13, userInfo: [NSLocalizedDescriptionKey: "No available audio input. Please connect a microphone or enable audio input routing."])
        }
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            cleanupOnFailure()
            throw error
        }

        // Prepare recognition
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { throw NSError(domain: "SpeechManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create recognition request"]) }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        tapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            cleanupOnFailure()
            throw error
        }
        transcript = ""

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    self.stopRecording()
                }
            }
        }

        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cleanupOnFailure() {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        _ = try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speak(_ text: String, languageCode: String?, rate: Double) {
        let utterance = AVSpeechUtterance(string: text)
        let requested = (languageCode?.isEmpty == false) ? languageCode! : Locale.autoupdatingCurrent.identifier
        // Prefer exact voice; otherwise fall back to any installed voice with same language prefix
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let selectedVoice = AVSpeechSynthesisVoice(language: requested)
            ?? voices.first(where: { $0.language == requested })
            ?? voices.first(where: { voice in
                let prefix = String(requested.prefix(2))
                return voice.language.hasPrefix(prefix)
            })
        // If nil, system default voice will be used; this avoids crashes and uses best available
        utterance.voice = selectedVoice
        // Clamp rate to Apple-recommended range
        let clamped = max(0.1, min(rate, 0.7))
        utterance.rate = Float(clamped)
        synthesizer.speak(utterance)
    }
}

