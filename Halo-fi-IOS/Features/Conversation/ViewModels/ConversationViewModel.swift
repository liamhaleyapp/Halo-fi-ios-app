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
        // WP7 — one thread for the chat tab and the voice modal.
        self.store = store ?? ConversationTranscriptStore.shared

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
        // WP7 — hands-free is the default inside the voice modal; push-to-
        // talk remains a choice in Settings → Preferences.
        let raw = UserDefaults.standard.string(forKey: "conversationMode") ?? "hands_free"
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
        // WP7 — the thread persists; only the live draft is dropped.
        store.discardDraft()
    }

    // MARK: - WP7 — chat thread + Start/Stop

    /// Connect silently (no greeting) so a typed message can go out from
    /// the Agent tab without opening the voice modal.
    func connectForText() async {
        guard !coordinator.isConnected else { return }
        let raw = UserDefaults.standard.string(forKey: "conversationMode") ?? "hands_free"
        coordinator.setConversationMode(ConversationMode.from(raw))
        let player = StreamingAudioPlayer()
        player.observeVoiceOverStatus()
        coordinator.configure(streamingAudioPlayer: player, audioFeedback: audioFeedback, transcriptStore: store)
        await coordinator.connect(skipGreeting: true)
    }

    var isSessionActive: Bool { coordinator.isConnected }

    /// The voice modal's primary control: Stop ends the session (mic and
    /// speech off); Start reconnects and listens.
    func toggleSession() async {
        if isSessionActive {
            coordinator.endConversation()
            UIAccessibility.post(notification: .announcement, argument: "Conversation stopped.")
        } else {
            await onAppear(skipGreeting: true)
            // connect() returns before connection_ack; listening needs .idle.
            for _ in 0..<60 where coordinator.state == .connecting {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if coordinator.state == .idle {
                await coordinator.startListening()
            }
        }
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
                case .listening:
                    coordinator.setMicMuted(!coordinator.isMicMuted)
                case .idle:
                    // The button reads "Start listening" here, so do that:
                    // unmute if needed and listen (it used to mute instead).
                    if coordinator.isMicMuted { coordinator.setMicMuted(false) }
                    await coordinator.startListening()
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
