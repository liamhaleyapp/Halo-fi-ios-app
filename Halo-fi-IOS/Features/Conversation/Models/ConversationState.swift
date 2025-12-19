//
//  ConversationState.swift
//  Halo-fi-IOS
//
//  Represents the lifecycle state of a conversation session.
//  Separate from InteractionMode which handles voice vs text UI mode.
//

import Foundation

/// Conversation lifecycle states managed by ConversationCoordinator
enum ConversationState: Equatable {
    /// Ready to start, not connected to backend
    case idle

    /// Establishing connection to backend
    case connecting

    /// Microphone active, recording user speech
    case listening

    /// Request sent, awaiting server response
    case processing

    /// Agent response is being spoken via TTS
    case speaking

    /// Connection dropped, can attempt reconnect
    case disconnected

    /// Microphone permission not granted
    case permissionNeeded

    /// Error state with descriptive message
    case error(String)
}

// MARK: - Display Helpers

extension ConversationState {
    /// User-facing status text for the mic button label
    var displayText: String {
        switch self {
        case .idle:
            return "Tap to talk"
        case .connecting:
            return "Connecting..."
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .speaking:
            return "Speaking..."
        case .disconnected:
            return "Disconnected"
        case .permissionNeeded:
            return "Microphone needed"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    /// VoiceOver announcement text for state changes
    var accessibilityAnnouncement: String {
        switch self {
        case .idle:
            return "Ready to start conversation"
        case .connecting:
            return "Connecting to Halo"
        case .listening:
            return "Listening"
        case .processing:
            return "Processing your request"
        case .speaking:
            return "Halo is responding"
        case .disconnected:
            return "Connection lost"
        case .permissionNeeded:
            return "Microphone permission is required"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    /// Whether the mic button should be enabled
    var isMicEnabled: Bool {
        switch self {
        case .idle, .listening:
            return true
        case .connecting, .processing, .speaking, .disconnected, .permissionNeeded, .error:
            return false
        }
    }

    /// Whether text input should be enabled
    var isTextInputEnabled: Bool {
        switch self {
        case .idle, .listening:
            return true
        case .connecting, .processing, .speaking, .disconnected, .permissionNeeded, .error:
            return false
        }
    }
}
