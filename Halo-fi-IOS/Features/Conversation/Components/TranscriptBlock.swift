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
                    .italic(entry.speaker.isDraft)
                    .foregroundColor(entry.speaker.isDraft ? .secondary : .primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Streaming indicator (for agent) or listening indicator (for draft)
                if entry.isStreaming {
                    if entry.speaker.isDraft {
                        listeningIndicator
                    } else {
                        streamingIndicator
                    }
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

    @ViewBuilder
    private var listeningIndicator: some View {
        // Waveform bars for listening state
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 3, height: listeningBarHeight(for: index))
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: entry.isStreaming
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func listeningBarHeight(for index: Int) -> CGFloat {
        // Varying heights for waveform effect
        let heights: [CGFloat] = [8, 14, 10, 12]
        return heights[index % heights.count]
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // Draft (live transcription)
        TranscriptBlock(entry: TranscriptEntry(
            id: UUID(),
            speaker: .userDraft,
            text: "What's my checking...",
            timestamp: Date(),
            isStreaming: true
        ))

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
