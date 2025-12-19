//
//  TranscriptBlock.swift
//  Halo-fi-IOS
//
//  Large, high-contrast transcript block for accessibility.
//  NOT a chat bubble - designed for screen reader friendliness.
//
//  Each block is a single accessibility element with:
//  - accessibilityLabel: "Halo said" / "You said"
//  - accessibilityValue: message content
//  - accessibilityHint: "Double tap to copy"
//

import SwiftUI

struct TranscriptBlock: View {
    let entry: TranscriptEntry

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Speaker label + timestamp
            HStack {
                Text(entry.speakerLabel)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(entry.speaker.labelColor)

                Spacer()

                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Message text
            HStack(alignment: .top, spacing: 8) {
                Text(entry.text)
                    .font(.title3)
                    .fontWeight(.regular)
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Streaming indicator
                if entry.isStreaming {
                    streamingIndicator
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.speaker.backgroundColor)
        .cornerRadius(12)
        // Single accessibility element
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.accessibilityLabel)
        .accessibilityValue(entry.accessibilityValue)
        .accessibilityHint(entry.accessibilityHint)
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                    .opacity(0.6)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: entry.isStreaming
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        TranscriptBlock(entry: .user("What's my checking account balance?"))

        TranscriptBlock(entry: .agent(
            "Your checking account balance is $1,234.56. Would you like me to show recent transactions?",
            isStreaming: false
        ))

        TranscriptBlock(entry: .agent(
            "Let me check that for you...",
            isStreaming: true
        ))

        TranscriptBlock(entry: .system("Connected to Halo"))
    }
    .padding()
}
