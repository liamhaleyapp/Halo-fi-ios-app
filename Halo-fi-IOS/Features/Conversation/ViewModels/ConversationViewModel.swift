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

@Observable
@MainActor
final class ConversationViewModel {
    // MARK: - Dependencies

    let coordinator: ConversationCoordinator
    let store: ConversationTranscriptStore

    // MARK: - Local State

    var textInput: String = ""
    var showingMoreMenu = false
    var showingHelp = false

    // MARK: - Computed Properties (from Coordinator)

    var state: ConversationState { coordinator.state }
    var interactionMode: InteractionMode { coordinator.interactionMode }
    var isConnected: Bool { coordinator.isConnected }
    var isMuted: Bool { coordinator.isMuted }
    var isPrivacyMode: Bool { coordinator.isPrivacyMode }

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

    func onAppear() async {
        // Configure services if needed
        let speechService = SpeechSynthesisService()
        let audioFeedback = AudioFeedbackService()
        coordinator.configure(
            speechService: speechService,
            audioFeedback: audioFeedback,
            transcriptStore: store
        )

        // Connect to backend
        await coordinator.connect()
    }

    func onDisappear() {
        coordinator.disconnect()
        store.reset()
    }

    // MARK: - Actions

    func toggleMicButton() {
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

    func toggleMute() {
        coordinator.setMuted(!isMuted)
    }

    func togglePrivacyMode() {
        coordinator.setPrivacyMode(!isPrivacyMode)
    }

    func copyEntry(_ entry: TranscriptEntry) {
        UIPasteboard.general.string = entry.text

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
        case .idle, .listening:
            return true
        default:
            return false
        }
    }

    var canSendText: Bool {
        isTextInputEnabled && !textInput.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
