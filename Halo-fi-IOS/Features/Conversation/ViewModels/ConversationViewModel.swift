//
//  ConversationViewModel.swift
//  Halo-fi-IOS
//
//  ViewModel for ConversationView.
//  Wires coordinator events to transcript store.
//  UI binds to store.entries and calls coordinator methods.
//

import Foundation
import UIKit
import SwiftUI

@Observable
@MainActor
final class ConversationViewModel {
    // MARK: - Dependencies

    let coordinator: ConversationCoordinator
    let store: ConversationTranscriptStore
    private let audioFeedback = AudioFeedbackService()

    // MARK: - Local State

    var textInput: String = ""
    var showingMoreMenu = false
    var showingHelp = false

    // MARK: - Computed Properties (from Coordinator)

    var state: ConversationState { coordinator.state }
    var interactionMode: InteractionMode { coordinator.interactionMode }
    var isConnected: Bool { coordinator.isConnected }
    var isMuted: Bool { coordinator.isMuted }
    var isMicMuted: Bool { coordinator.isMicMuted }
    var isPrivacyMode: Bool { coordinator.isPrivacyMode }
    var conversationMode: ConversationMode { coordinator.conversationMode }

    var isHandsFree: Bool { conversationMode == .handsFree }

    // MARK: - Computed Properties (from Store)

    var entries: [TranscriptEntry] { store.entries }

    // MARK: - Initialization

    init(
        coordinator: ConversationCoordinator? = nil,
        store: ConversationTranscriptStore? = nil
    ) {
        self.coordinator = coordinator ?? ConversationCoordinator.shared
        self.store = store ?? ConversationTranscriptStore()

        // Wire coordinator events to store
        let transcriptStore = self.store
        self.coordinator.onEvent = { [weak transcriptStore] event in
            transcriptStore?.append(event)
        }
    }

    // MARK: - Lifecycle

    func onAppear(skipGreeting: Bool = false, customGreetingId: String? = nil) async {
        // Play audio feedback when conversation opens
        audioFeedback.playConversationStartFeedback()

        // Pull the user's conversation-style preference (set in
        // Settings → Preferences) and pin it on the coordinator. We
        // read from @AppStorage directly via UserDefaults rather than
        // instantiating a property here so the value picks up changes
        // made between conversations without view-lifecycle plumbing.
        let raw = UserDefaults.standard.string(forKey: "conversationMode")
        coordinator.setConversationMode(ConversationMode.from(raw))

        // Configure services
        let streamingAudioPlayer = StreamingAudioPlayer()
        streamingAudioPlayer.observeVoiceOverStatus()
        coordinator.configure(
            streamingAudioPlayer: streamingAudioPlayer,
            audioFeedback: audioFeedback,
            transcriptStore: store
        )

        // Wire up accessibility feedback callbacks
        store.onAgentMessageComplete = { [weak self] in
            self?.audioFeedback.playAgentMessageCompleteFeedback()
        }

        // Connect to backend.
        // - Phase 12: skip the welcome when a quick-action button is
        //   about to send a pre-prompt the user already triggered.
        // - Phase 9c: a customGreetingId asks the backend to send a
        //   fixed canonical greeting instead — used by entry points
        //   like "Log with voice" that want Halo to open with a
        //   specific question, not "Good evening".
        await coordinator.connect(
            skipGreeting: skipGreeting,
            customGreetingId: customGreetingId
        )
    }

    func onDisappear() {
        coordinator.disconnect()
        store.reset()
    }

    // MARK: - Actions

    func toggleMicButton() {
        // Hands-free reuses the same big button as a mic-mute toggle:
        // the conversation auto-flows turn-to-turn, so the user only
        // ever needs to silence themselves (side conversation, baby
        // crying, etc.) — they don't manually start / stop turns.
        // Still respect "stop speaking" while Halo is talking so a
        // user can skip a long response.
        if isHandsFree {
            Task {
                switch state {
                case .speaking:
                    coordinator.stopSpeaking()
                case .listening, .idle:
                    coordinator.setMicMuted(!coordinator.isMicMuted)
                    if !coordinator.isMicMuted && state == .idle {
                        // Manual unmute from idle resumes listening
                        // explicitly — the auto-resume path only fires
                        // after Halo finishes speaking.
                        await coordinator.startListening()
                    }
                default:
                    break
                }
            }
            return
        }

        Task {
            switch state {
            case .listening:
                coordinator.stopListening()
            case .idle:
                await coordinator.startListening()
            case .speaking:
                // Stop current TTS (skip this message)
                coordinator.stopSpeaking()
            default:
                break
            }
        }
    }

    /// Hands-free explicit end. The X close button in the header
    /// already does this on dismiss; the dedicated "End Conversation"
    /// button gives users a more discoverable affordance.
    func endConversation() {
        coordinator.endConversation()
    }

    func switchToTextMode() {
        coordinator.setInteractionMode(.text)
    }

    func switchToVoiceMode() {
        coordinator.setInteractionMode(.voice)
    }

    func sendTextMessage() {
        let message = textInput.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return }

        textInput = ""

        Task {
            await coordinator.sendText(message)
        }
    }

    /// Send a text message programmatically (e.g., from quick action buttons)
    func sendText(_ message: String) async {
        await coordinator.sendText(message)
    }

    func toggleMute() {
        coordinator.setMuted(!isMuted)
    }

    func togglePrivacyMode() {
        coordinator.setPrivacyMode(!isPrivacyMode)
    }

    func copyEntry(_ entry: TranscriptEntry) {
        // Copy locally only (no Handoff / Universal Clipboard) and auto-expire
        // after 60s — a transcript line can contain a balance (F048).
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": entry.text]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(60)
            ]
        )

        // Announce for accessibility
        UIAccessibility.post(
            notification: .announcement,
            argument: "Message copied"
        )
    }

    func showMoreMenu() {
        showingMoreMenu = true
    }

    func showHelpView() {
        showingHelp = true
    }

    // MARK: - State Helpers

    var isMicEnabled: Bool {
        switch state {
        case .idle, .listening, .speaking:
            return true
        default:
            return false
        }
    }

    var isTextInputEnabled: Bool {
        switch state {
        case .idle, .listening, .speaking:
            return true
        default:
            return false
        }
    }

    var canSendText: Bool {
        isTextInputEnabled && !textInput.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
