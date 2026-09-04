//
//  ConversationView.swift
//  Halo-fi-IOS
//
//  Unified voice-first conversation interface.
//  Replaces separate VoiceConversationView and AgentChatView.
//
//  Features:
//  - Voice-first with large mic button
//  - Transcript display (not chat bubbles)
//  - Inline text input (secondary)
//  - Full accessibility support
//

import SwiftUI

struct ConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ConversationViewModel()

    /// Optional prompt to auto-send after connecting (e.g., from quick action buttons)
    var initialPrompt: String? = nil
    /// Phase 9c — when set, the backend sends a fixed canonical
    /// greeting keyed by this id instead of the LLM-built welcome
    /// AND no priming user-message is sent. Use this for entry
    /// points like "Log with voice" where Halo should open with a
    /// specific question. Currently supported ids: "deduction_intake".
    var customGreetingId: String? = nil

    /// True when VoiceOver should NOT read the transcript — i.e.
    /// while Halo is speaking OR while the mic is open. Prevents
    /// the speaker→mic feedback loop where VoiceOver-rendered
    /// transcript text bleeds into STT and gets transcribed as user
    /// input on the next turn.
    private var shouldHideTranscriptFromVoiceOver: Bool {
        switch viewModel.state {
        case .speaking, .listening, .processing, .connecting:
            return true
        default:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ConversationHeader(
                isConnected: viewModel.isConnected,
                isMuted: viewModel.isMuted,
                onMuteToggle: viewModel.toggleMute,
                onMoreTap: viewModel.showMoreMenu,
                onClose: { dismiss() }
            )

            // Transcript.
            //
            // Hide from VoiceOver while Halo is actively speaking
            // OR while the mic is hot (.listening, .processing). The
            // microphone picks up VoiceOver's voice through the
            // device speaker → STT mistakes it for the user → transcripts
            // get contaminated and (worse) Halo's own response gets
            // re-spoken in a feedback loop. Halo's TTS already covers
            // the audio channel for blind users; VoiceOver here would
            // be redundant AND harmful.
            //
            // The mic button + close button stay accessible (those are
            // the only interactions VoiceOver users need in here).
            //
            // We re-enable VoiceOver on the transcript when the
            // session is .idle / .disconnected / .error so users can
            // review what was said via VoiceOver scrolling.
            TranscriptView(
                entries: viewModel.entries,
                onCopyEntry: viewModel.copyEntry,
                isProcessing: viewModel.state == .processing
            )
            .accessibilityElement(children: shouldHideTranscriptFromVoiceOver ? .ignore : .contain)
            .accessibilityHidden(shouldHideTranscriptFromVoiceOver)

            // Input area (voice or text mode)
            inputArea
        }
        .background(Color(.systemBackground))
        .onAppear {
            viewModel.coordinator.setVoiceModalPresented(true)
            Task {
                // Three entry modes:
                //  1. customGreetingId set  → backend sends a fixed
                //     canonical greeting (e.g. deduction_intake's
                //     "What expense would you like to log?"); no
                //     priming user-message sent.
                //  2. initialPrompt set     → Phase 12 quick-action;
                //     backend skips the welcome and the user's first
                //     message is the prompt itself.
                //  3. Neither               → standard welcome flow.
                let hasCustom = (customGreetingId?.isEmpty == false)
                let hasPrompt = !hasCustom && (initialPrompt?.isEmpty == false)
                await viewModel.onAppear(
                    skipGreeting: hasPrompt,
                    customGreetingId: customGreetingId
                )
                if hasPrompt, let prompt = initialPrompt, !prompt.isEmpty {
                    await viewModel.sendText(prompt)
                }
            }
        }
        .onDisappear {
            viewModel.coordinator.setVoiceModalPresented(false)
            viewModel.onDisappear()
        }
        .accessibilityAction(.escape) { dismiss() }
        .sheet(isPresented: $viewModel.showingMoreMenu) {
            ConversationMoreMenu(
                isPrivacyMode: viewModel.isPrivacyMode,
                onPrivacyModeToggle: viewModel.togglePrivacyMode,
                onHelpTap: viewModel.showHelpView
            )
            .presentationDetents([.medium])
        }
        .dynamicTypeSize(.medium ... .accessibility5)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - WP7 — Start / Stop conversation (hands-free primary control)

    private var sessionButton: some View {
        let active = viewModel.isSessionActive
        return Button {
            Task { await viewModel.toggleSession() }
        } label: {
            Label(active ? "Stop conversation" : "Start conversation",
                  systemImage: active ? "stop.circle.fill" : "play.circle.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(active ? Color.haloNegative : Color.accentColor)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityHint(active
            ? "Ends the voice session. Your transcript stays."
            : "Reconnects and starts listening.")
    }

    // MARK: - Input Area

    @ViewBuilder
    private var inputArea: some View {
        switch viewModel.interactionMode {
        case .voice:
            // Hands-free turns the bottom row into a mute label and
            // recolors the mic button as a mute toggle. Conversation
            // teardown happens via the header's X close button — no
            // dedicated End button needed.
            let handsFree: VoiceModeInputArea.HandsFreeOptions? =
                viewModel.isHandsFree
                    ? .init(isMicMuted: viewModel.isMicMuted)
                    : nil
            VStack(spacing: 0) {
                if viewModel.isHandsFree {
                    sessionButton
                }
                VoiceModeInputArea(
                    state: viewModel.state,
                    isEnabled: viewModel.isMicEnabled,
                    onMicTap: viewModel.toggleMicButton,
                    onSwitchToText: viewModel.switchToTextMode,
                    handsFree: handsFree
                )
            }
            .background(Color(.systemBackground))

        case .text:
            TextInputArea(
                text: $viewModel.textInput,
                state: viewModel.state,
                isEnabled: viewModel.isTextInputEnabled,
                onSend: viewModel.sendTextMessage,
                onSwitchToVoice: viewModel.switchToVoiceMode,
                onStopSpeaking: viewModel.toggleMicButton
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ConversationView()
} 

#Preview("With Messages") {
    let viewModel = ConversationViewModel()
    // Add some sample entries for preview
    viewModel.store.append(.userText("What's my balance?"))
    viewModel.store.append(.agentFinal("Your checking account balance is $1,234.56", id: UUID()))

    return ConversationView()
}
