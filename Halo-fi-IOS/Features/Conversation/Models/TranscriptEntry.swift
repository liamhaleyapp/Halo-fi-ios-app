//
//  TranscriptEntry.swift
//  Halo-fi-IOS
//
//  Renderable transcript entry derived from ConversationEvent.
//  TranscriptStore transforms raw events into these entries for UI display.
//
//  Design: Mutable text property allows streaming updates without creating new entries.
//

import Foundation

/// Renderable transcript entry for UI display
struct TranscriptEntry: Identifiable, Equatable {
    let id: UUID
    let speaker: Speaker
    var text: String
    let timestamp: Date
    var isStreaming: Bool

    /// Speaker type for transcript entries
    enum Speaker: Equatable {
        case user
        case agent
        case system
    }
}

// MARK: - Initializers

extension TranscriptEntry {
    /// Create a user message entry
    static func user(_ text: String, id: UUID = UUID(), timestamp: Date = Date()) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            speaker: .user,
            text: text,
            timestamp: timestamp,
            isStreaming: false
        )
    }

    /// Create an agent message entry (can be streaming)
    static func agent(
        _ text: String,
        id: UUID = UUID(),
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            speaker: .agent,
            text: text,
            timestamp: timestamp,
            isStreaming: isStreaming
        )
    }

    /// Create a system message entry
    static func system(_ text: String, id: UUID = UUID(), timestamp: Date = Date()) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            speaker: .system,
            text: text,
            timestamp: timestamp,
            isStreaming: false
        )
    }
}

// MARK: - Display Helpers

extension TranscriptEntry {
    /// Speaker label for display (e.g., "You said", "Halo said")
    var speakerLabel: String {
        switch speaker {
        case .user:
            return "You said"
        case .agent:
            return "Halo said"
        case .system:
            return "System"
        }
    }

    /// VoiceOver accessibility label for the entry
    var accessibilityLabel: String {
        speakerLabel
    }

    /// VoiceOver accessibility value (the message content)
    var accessibilityValue: String {
        text
    }

    /// VoiceOver accessibility hint
    var accessibilityHint: String {
        "Double tap to copy"
    }
}

// MARK: - Speaker Color Helpers

import SwiftUI

extension TranscriptEntry.Speaker {
    /// Background color for the transcript block
    var backgroundColor: Color {
        switch self {
        case .user:
            return Color(.systemGray5)
        case .agent:
            return Color.blue.opacity(0.1)
        case .system:
            return Color.orange.opacity(0.1)
        }
    }

    /// Text color for the speaker label
    var labelColor: Color {
        switch self {
        case .user:
            return .secondary
        case .agent:
            return .blue
        case .system:
            return .orange
        }
    }
}
