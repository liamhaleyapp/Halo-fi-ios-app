//
//  TextInputArea.swift
//  Halo-fi-IOS
//
//  Inline text input area for text mode.
//  Features:
//  - Expandable text field
//  - Send button
//  - Compact mic button to switch back to voice
//  - Auto-focus on expand
//

import SwiftUI

struct TextInputArea: View {
    @Binding var text: String
    let state: ConversationState
    let isEnabled: Bool
    let onSend: () -> Void
    let onSwitchToVoice: () -> Void
    var onStopSpeaking: (() -> Void)?

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Compact mic button - stops TTS when speaking, otherwise switches to voice
            MicButtonCompact(
                state: state,
                isEnabled: (isEnabled && state != .processing) || state == .speaking,
                onTap: {
                    if state == .speaking {
                        onStopSpeaking?()
                    } else {
                        onSwitchToVoice()
                    }
                }
            )

            // Text field
            TextField("Type your message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .lineLimit(1...4)
                .focused($isTextFieldFocused)
                .disabled(!isEnabled)
                .accessibilityLabel("Message input")
                .accessibilityHint("Enter your message to Halo")

            // Send button
            sendButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .onAppear {
            // Auto-focus when appearing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        Button(action: {
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            onSend()
        }) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(canSend ? .blue : .gray)
        }
        .disabled(!canSend)
        .accessibilityLabel("Send message")
        .accessibilityHint(canSend ? "Double tap to send your message" : "Enter a message first")
    }

    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespaces).isEmpty && state != .processing
    }
}

// MARK: - Mode Toggle Button

struct ModeToggleButton: View {
    let mode: InteractionMode
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: mode.toggleButtonIcon)
                    .font(.body)

                Text(mode.toggleButtonLabel)
                    .font(.body)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(20)
        }
        .accessibilityLabel(mode.toggleButtonLabel)
        .accessibilityHint(mode.toggleButtonHint)
    }
}

// MARK: - Voice Mode Input Area

struct VoiceModeInputArea: View {
    let state: ConversationState
    let isEnabled: Bool
    let onMicTap: () -> Void
    let onSwitchToText: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Large mic button
            MicButton(
                state: state,
                isEnabled: isEnabled,
                onTap: onMicTap
            )

            // Type instead toggle
            ModeToggleButton(
                mode: .voice,
                onToggle: onSwitchToText
            )
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        VoiceModeInputArea(
            state: .idle,
            isEnabled: true,
            onMicTap: { },
            onSwitchToText: { }
        )

        Divider()

        TextInputArea(
            text: .constant(""),
            state: .idle,
            isEnabled: true,
            onSend: { },
            onSwitchToVoice: { }
        )

        TextInputArea(
            text: .constant("What's my balance?"),
            state: .idle,
            isEnabled: true,
            onSend: { },
            onSwitchToVoice: { }
        )
    }
}
