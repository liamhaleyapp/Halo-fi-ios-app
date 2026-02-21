//
//  AudioFeedbackService.swift
//  Halo-fi-IOS
//
//  Haptic and audio feedback for conversation state changes.
//  Provides earcons (short audio cues) and haptic feedback.
//

import AudioToolbox
import AVFoundation
import UIKit

@MainActor
final class AudioFeedbackService {
    // MARK: - Haptic Generators

    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    // MARK: - Audio Players

    private var startListeningSound: AVAudioPlayer?
    private var stopListeningSound: AVAudioPlayer?
    private var agentTypingSound: AVAudioPlayer?
    private var agentCompleteSound: AVAudioPlayer?
    private var tabSwitchSound: AVAudioPlayer?
    private var conversationStartSound: AVAudioPlayer?

    // MARK: - Initialization

    init() {
        prepare()
        loadSounds()
    }

    // MARK: - Preparation

    private func prepare() {
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    private func loadSounds() {
        // Load custom earcon sounds from Resources/Sounds/
        if let url = Bundle.main.url(forResource: "listening_start", withExtension: "aif") {
            startListeningSound = try? AVAudioPlayer(contentsOf: url)
            startListeningSound?.prepareToPlay()
            startListeningSound?.volume = 0.7
        }

        if let url = Bundle.main.url(forResource: "listening_stop", withExtension: "aif") {
            stopListeningSound = try? AVAudioPlayer(contentsOf: url)
            stopListeningSound?.prepareToPlay()
            stopListeningSound?.volume = 0.7
        }

        if let url = Bundle.main.url(forResource: "agent_typing", withExtension: "aif") {
            agentTypingSound = try? AVAudioPlayer(contentsOf: url)
            agentTypingSound?.prepareToPlay()
            agentTypingSound?.volume = 0.5
        }

        if let url = Bundle.main.url(forResource: "agent_complete", withExtension: "mp3") {
            agentCompleteSound = try? AVAudioPlayer(contentsOf: url)
            agentCompleteSound?.prepareToPlay()
            agentCompleteSound?.volume = 0.6
        }

        if let url = Bundle.main.url(forResource: "tab_switch", withExtension: "wav") {
            tabSwitchSound = try? AVAudioPlayer(contentsOf: url)
            tabSwitchSound?.prepareToPlay()
            tabSwitchSound?.volume = 0.5
        }

        if let url = Bundle.main.url(forResource: "pop_drip", withExtension: "aif") {
            conversationStartSound = try? AVAudioPlayer(contentsOf: url)
            conversationStartSound?.prepareToPlay()
            conversationStartSound?.volume = 0.6
        }
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
        // Single medium haptic - subtle but noticeable
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred()

        // Custom earcon sound
        startListeningSound?.currentTime = 0
        startListeningSound?.play()
    }

    private func playProcessingFeedback() {
        // Medium haptic
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred()
    }

    private func playIdleFeedback() {
        // Medium haptic - done recording
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred()

        // Custom earcon sound
        stopListeningSound?.currentTime = 0
        stopListeningSound?.play()
    }

    private func playErrorFeedback() {
        // Error haptic
        notificationGenerator.notificationOccurred(.error)
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
        mediumImpactGenerator.impactOccurred(intensity: intensity)
    }

    // MARK: - Agent Feedback

    /// Play feedback when agent starts typing/responding
    func playAgentTypingFeedback() {
        // Light haptic - agent is responding
        lightImpactGenerator.prepare()
        lightImpactGenerator.impactOccurred()

        // Custom earcon sound
        agentTypingSound?.currentTime = 0
        agentTypingSound?.play()
    }

    /// Play feedback when agent message is complete
    func playAgentMessageCompleteFeedback() {
        // Success haptic
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)

        // Custom earcon sound
        agentCompleteSound?.currentTime = 0
        agentCompleteSound?.play()
    }

    // MARK: - Navigation Feedback

    /// Play feedback for tab switching
    func playTabSwitchFeedback() {
        // Medium haptic for noticeable feedback
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred()

        // Custom earcon sound
        tabSwitchSound?.currentTime = 0
        tabSwitchSound?.play()
    }

    // MARK: - Conversation Feedback

    /// Play feedback when conversation view opens
    func playConversationStartFeedback() {
        // Success haptic to indicate conversation is ready
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)

        // Custom earcon sound
        conversationStartSound?.currentTime = 0
        conversationStartSound?.play()
    }

    // MARK: - Button Feedback

    /// Play light haptic feedback for button taps
    func playButtonTapFeedback() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }
}

// MARK: - Shared Instance

extension AudioFeedbackService {
    /// Shared instance for global haptic feedback access
    static let shared = AudioFeedbackService()
}
