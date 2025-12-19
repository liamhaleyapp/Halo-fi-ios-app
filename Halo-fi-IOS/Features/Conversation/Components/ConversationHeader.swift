//
//  ConversationHeader.swift
//  Halo-fi-IOS
//
//  Header bar for the conversation view.
//  Features:
//  - Connection status indicator
//  - Mute toggle
//  - More menu (help, privacy info)
//  - Close button
//

import SwiftUI

struct ConversationHeader: View {
    let isConnected: Bool
    let isMuted: Bool
    let onMuteToggle: () -> Void
    let onMoreTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Close button
            closeButton

            Spacer()

            // Connection status
            connectionStatus

            Spacer()

            // Mute toggle
            muteButton

            // More menu
            moreButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    // MARK: - Subviews

    @ViewBuilder
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.body.weight(.medium))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray6))
                .clipShape(Circle())
        }
        .accessibilityLabel("Close conversation")
        .accessibilityHint("Double tap to end conversation and return")
    }

    @ViewBuilder
    private var connectionStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(isConnected ? "Connected" : "Disconnected")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isConnected ? "Connected to Halo" : "Disconnected from Halo")
    }

    @ViewBuilder
    private var muteButton: some View {
        Button(action: onMuteToggle) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.body)
                .foregroundColor(isMuted ? .red : .primary)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray6))
                .clipShape(Circle())
        }
        .accessibilityLabel(isMuted ? "Unmute responses" : "Mute responses")
        .accessibilityHint(isMuted ? "Double tap to hear spoken responses" : "Double tap to silence spoken responses")
        .accessibilityAddTraits(isMuted ? .isSelected : [])
    }

    @ViewBuilder
    private var moreButton: some View {
        Button(action: onMoreTap) {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray6))
                .clipShape(Circle())
        }
        .accessibilityLabel("More options")
        .accessibilityHint("Double tap for help and privacy settings")
    }
}

// MARK: - More Menu Sheet

struct ConversationMoreMenu: View {
    let isPrivacyMode: Bool
    let onPrivacyModeToggle: () -> Void
    let onHelpTap: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Privacy mode toggle
                Section {
                    Toggle(isOn: Binding(
                        get: { isPrivacyMode },
                        set: { _ in onPrivacyModeToggle() }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Privacy Mode")
                                .font(.body)

                            Text("Halo won't speak responses aloud")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityHint(isPrivacyMode
                        ? "Currently on. Double tap to allow spoken responses"
                        : "Currently off. Double tap to silence spoken responses"
                    )
                } header: {
                    Text("Privacy")
                }

                // Info section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About Voice Conversations")
                            .font(.headline)

                        Text("Halo may read your account balances and transaction details aloud. Use Privacy Mode in public spaces.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Important")
                }

                // Help
                Section {
                    Button(action: {
                        onHelpTap()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("Get Help")
                        }
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ConversationHeader(
            isConnected: true,
            isMuted: false,
            onMuteToggle: { },
            onMoreTap: { },
            onClose: { }
        )

        ConversationHeader(
            isConnected: false,
            isMuted: true,
            onMuteToggle: { },
            onMoreTap: { },
            onClose: { }
        )

        Spacer()
    }
}
