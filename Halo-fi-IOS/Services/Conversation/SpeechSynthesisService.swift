//
//  SpeechSynthesisService.swift
//  Halo-fi-IOS
//
//  Text-to-speech service for agent responses.
//  Uses AVSpeechSynthesizer for local TTS.
//

import AVFoundation
import UIKit

@MainActor
final class SpeechSynthesisService: NSObject {
    // MARK: - Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var isMuted: Bool = false

    /// Callback when speaking finishes
    var onSpeakingFinished: (() -> Void)?

    /// Whether currently speaking
    private(set) var isSpeaking: Bool = false

    // MARK: - Initialization

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public Methods

    /// Speak the given text
    func speak(_ text: String) {
        guard !isMuted else {
            onSpeakingFinished?()
            return
        }

        // Don't speak if VoiceOver is running (let user read transcript)
        guard !UIAccessibility.isVoiceOverRunning else {
            onSpeakingFinished?()
            return
        }

        // Configure audio session for speaking
        configureAudioSessionForSpeaking()

        // Create utterance
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Speak
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stop speaking immediately
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        restoreAudioSession()
    }

    /// Set muted state
    func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted {
            stop()
        }
    }

    // MARK: - Audio Session Management

    private func configureAudioSessionForSpeaking() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            Logger.error("Failed to configure audio session for speaking: \(error)")
        }
    }

    private func restoreAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Logger.error("Failed to restore audio session: \(error)")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesisService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            restoreAudioSession()
            onSpeakingFinished?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            restoreAudioSession()
            onSpeakingFinished?()
        }
    }
}
