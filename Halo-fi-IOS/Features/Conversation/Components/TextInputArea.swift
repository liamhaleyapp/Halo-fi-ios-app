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
    // Scales with Dynamic Type (App Store Guideline 4).
    @ScaledMetric(relativeTo: .largeTitle) private var sendIconSize: CGFloat = 36
    @Binding var text: String
    let state: ConversationState
    let isEnabled: Bool
    let onSend: () -> Void
    let onSwitchToVoice: () -> Void
    var onStopSpeaking: (() -> Void)?
    /// Raise the keyboard on appear. The voice modal's text mode wants it;
    /// the Agent tab must not (VoiceOver has to land on the header first).
    var autoFocus: Bool = true
    /// Agent tab: the mic is the primary voice entry (purple, larger).
    var prominentVoice: Bool = false

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
                },
                prominent: prominentVoice
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
            guard autoFocus else { return }
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
                .font(.system(size: sendIconSize))
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
    /// Hands-free only. When non-nil, the mic button renders as a
    /// mute toggle (slash icon, gray gradient) and a "Mic muted" /
    /// "Listening" status label appears below. The conversation is
    /// ended via the X close button in the header — no separate
    /// End button needed.
    var handsFree: HandsFreeOptions? = nil

    struct HandsFreeOptions {
        let isMicMuted: Bool
    }

    var body: some View {
        VStack(spacing: 16) {
            MicButton(
                state: state,
                isEnabled: isEnabled,
                onTap: onMicTap,
                appearMuted: handsFree?.isMicMuted ?? false
            )

            if let handsFree {
                Text(handsFree.isMicMuted ? "Mic muted — tap mic to unmute" : "Listening — tap mic to mute")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            } else {
                ModeToggleButton(
                    mode: .voice,
                    onToggle: onSwitchToText
                )
            }
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
