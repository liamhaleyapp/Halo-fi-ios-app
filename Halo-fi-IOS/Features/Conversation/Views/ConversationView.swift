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

            // Transcript
            TranscriptView(
                entries: viewModel.entries,
                onCopyEntry: viewModel.copyEntry,
                isProcessing: viewModel.state == .processing
            )

            // Input area (voice or text mode)
            inputArea
        }
        .background(Color(.systemBackground))
        .onAppear {
            Task {
                await viewModel.onAppear()
            }
        }
        .onDisappear {
            viewModel.onDisappear()
        }
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

    // MARK: - Input Area

    @ViewBuilder
    private var inputArea: some View {
        switch viewModel.interactionMode {
        case .voice:
            VoiceModeInputArea(
                state: viewModel.state,
                isEnabled: viewModel.isMicEnabled,
                onMicTap: viewModel.toggleMicButton,
                onSwitchToText: viewModel.switchToTextMode
            )
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
