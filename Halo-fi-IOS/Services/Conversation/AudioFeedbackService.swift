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

    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    // MARK: - Sound File URLs
    // We store URLs and create fresh AVAudioPlayer instances on each play,
    // so they're always created under the current audio session configuration.

    private var startListeningSoundURL: URL?
    private var stopListeningSoundURL: URL?
    private var agentTypingSoundURL: URL?
    private var agentCompleteSoundURL: URL?
    private var tabSwitchSoundURL: URL?
    private var conversationStartSoundURL: URL?

    /// Strong reference to the currently-playing AVAudioPlayer.
    /// Without this, ARC deallocates the player before it finishes.
    private var activePlayer: AVAudioPlayer?

    // MARK: - Initialization

    init() {
        prepare()
        loadSoundURLs()
    }

    // MARK: - Preparation

    private func prepare() {
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    private func loadSoundURLs() {
        startListeningSoundURL = Bundle.main.url(forResource: "listening_start", withExtension: "aif")
        stopListeningSoundURL = Bundle.main.url(forResource: "listening_stop", withExtension: "aif")
        agentTypingSoundURL = Bundle.main.url(forResource: "agent_typing", withExtension: "aif")
        agentCompleteSoundURL = Bundle.main.url(forResource: "agent_complete", withExtension: "mp3")
        tabSwitchSoundURL = Bundle.main.url(forResource: "tab_switch", withExtension: "wav")
        conversationStartSoundURL = Bundle.main.url(forResource: "pop_drip", withExtension: "aif")
    }

    /// Creates a fresh AVAudioPlayer and plays it immediately.
    /// A new player is created each time so it works regardless of
    /// audio session changes from VoiceService or StreamingAudioPlayer.
    private func playSound(_ url: URL?, volume: Float = 0.7) {
        guard let url else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            activePlayer = player  // Keep strong reference until next sound
            player.play()
        } catch {
            Logger.error("AudioFeedbackService: Failed to play sound: \(error.localizedDescription)")
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
        playSound(startListeningSoundURL, volume: 0.7)
    }

    private var processingPulseTask: Task<Void, Never>?

    private func playProcessingFeedback() {
        // Initial haptic + sound
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred()

        playSound(agentTypingSoundURL, volume: 0.5)

        // Start repeating haptic pulse while thinking
        startProcessingPulse()
    }

    private func startProcessingPulse() {
        stopProcessingPulse()
        processingPulseTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                guard !Task.isCancelled else { break }
                lightImpactGenerator.prepare()
                lightImpactGenerator.impactOccurred(intensity: 0.4)
            }
        }
    }

    /// Stop the processing pulse (call when response arrives)
    func stopProcessingPulse() {
        processingPulseTask?.cancel()
        processingPulseTask = nil
    }

    private func playIdleFeedback() {
        // Medium haptic - done recording
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred()

        // Custom earcon sound
        playSound(stopListeningSoundURL, volume: 0.7)
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
        playSound(agentTypingSoundURL, volume: 0.5)
    }

    /// Play feedback when agent message is complete
    func playAgentMessageCompleteFeedback() {
        // Success haptic
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)

        // Custom earcon sound
        playSound(agentCompleteSoundURL, volume: 0.6)
    }

    // MARK: - Navigation Feedback

    /// Play feedback for tab switching
    func playTabSwitchFeedback() {
        // Medium haptic for noticeable feedback
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred()

        // Custom earcon sound
        playSound(tabSwitchSoundURL, volume: 0.5)
    }

    // MARK: - Conversation Feedback

    /// Play feedback when conversation view opens
    func playConversationStartFeedback() {
        // Success haptic to indicate conversation is ready
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)

        // Custom earcon sound
        playSound(conversationStartSoundURL, volume: 0.6)
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
