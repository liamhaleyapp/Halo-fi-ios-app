//
//  AudioFeedbackService.swift
//  Halo-fi-IOS
//
//  Haptic and audio feedback for conversation state changes.
//  Provides earcons (short audio cues) and haptic feedback.
//

import AVFoundation
import UIKit

@MainActor
final class AudioFeedbackService {
    // MARK: - Haptic Generators

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    // MARK: - Audio Players (for future earcon support)

    private var startListeningSound: AVAudioPlayer?
    private var stopListeningSound: AVAudioPlayer?
    private var errorSound: AVAudioPlayer?

    // MARK: - Initialization

    init() {
        prepare()
        loadSounds()
    }

    // MARK: - Preparation

    private func prepare() {
        impactGenerator.prepare()
        notificationGenerator.prepare()
    }

    private func loadSounds() {
        // Placeholder for future earcon sound files
        // When sound files are added to Resources/Sounds/:
        //
        // if let url = Bundle.main.url(forResource: "earcon_start", withExtension: "wav") {
        //     startListeningSound = try? AVAudioPlayer(contentsOf: url)
        //     startListeningSound?.prepareToPlay()
        // }
        //
        // Similar for stopListeningSound and errorSound
    }

    // MARK: - State Change Feedback

    /// Provide feedback for a state change
    func feedbackForStateChange(_ state: ConversationState) {
        switch state {
        case .listening:
            playStartListeningFeedback()

        case .processing:
            playProcessingFeedback()

        case .speaking:
            // No feedback for speaking start (TTS handles this)
            break

        case .idle:
            // Light feedback when returning to idle from listening
            playIdleFeedback()

        case .error:
            playErrorFeedback()

        case .disconnected:
            playDisconnectedFeedback()

        case .connecting, .permissionNeeded:
            // No feedback for these states
            break
        }
    }

    // MARK: - Feedback Actions

    private func playStartListeningFeedback() {
        // Haptic
        impactGenerator.impactOccurred(intensity: 0.7)

        // Earcon (when available)
        startListeningSound?.play()
    }

    private func playProcessingFeedback() {
        // Light haptic
        impactGenerator.impactOccurred(intensity: 0.5)
    }

    private func playIdleFeedback() {
        // Very light haptic
        impactGenerator.impactOccurred(intensity: 0.3)

        // Earcon (when available)
        stopListeningSound?.play()
    }

    private func playErrorFeedback() {
        // Error haptic
        notificationGenerator.notificationOccurred(.error)

        // Earcon (when available)
        errorSound?.play()
    }

    private func playDisconnectedFeedback() {
        // Warning haptic
        notificationGenerator.notificationOccurred(.warning)
    }

    // MARK: - Success Feedback

    /// Play success feedback (e.g., message sent)
    func playSuccessFeedback() {
        notificationGenerator.notificationOccurred(.success)
    }

    // MARK: - Custom Haptic

    /// Play a custom impact
    func playImpact(intensity: CGFloat = 0.5) {
        impactGenerator.impactOccurred(intensity: intensity)
    }
}
