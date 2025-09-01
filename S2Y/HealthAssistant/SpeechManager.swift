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

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private let synthesizer = AVSpeechSynthesizer()

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
    }

    func startRecording(languageCode: String?) async throws {
        guard !isRecording else { return }

        // Determine locale
        let localeIdentifier = (languageCode?.isEmpty == false) ? languageCode! : Locale.autoupdatingCurrent.identifier
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw NSError(domain: "SpeechManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported language: \(localeIdentifier)"])
        }
        speechRecognizer = recognizer

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

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

        audioEngine.prepare()
        try audioEngine.start()
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
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speak(_ text: String, languageCode: String?, rate: Double) {
        let utterance = AVSpeechUtterance(string: text)
        let code = (languageCode?.isEmpty == false) ? languageCode! : Locale.autoupdatingCurrent.identifier
        utterance.voice = AVSpeechSynthesisVoice(language: code)
        // Clamp rate to Apple-recommended range
        let clamped = max(0.1, min(rate, 0.7))
        utterance.rate = Float(clamped)
        synthesizer.speak(utterance)
    }
}

