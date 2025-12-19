//
//  ConversationEvent.swift
//  Halo-fi-IOS
//
//  Event-based model for conversation timeline.
//  TranscriptStore transforms these events into renderable TranscriptEntry objects.
//
//  Key design: Separate delta from final events to prevent "partial overwrote final" bugs
//  and enable clean streaming merge logic in TranscriptStore.
//

import Foundation

/// Conversation events emitted by ConversationCoordinator
/// These are the source of truth; TranscriptEntry is derived for rendering
enum ConversationEvent: Identifiable, Equatable {
    // MARK: - User Events

    /// User sent a text message (final, complete)
    case userText(id: UUID, text: String, timestamp: Date)

    /// User speech transcription delta (partial, streaming)
    case userSpeechDelta(id: UUID, delta: String, timestamp: Date)

    /// User speech transcription final (complete)
    case userSpeechFinal(id: UUID, text: String, timestamp: Date)

    // MARK: - Agent Events

    /// Agent response text delta (partial, streaming)
    case agentTextDelta(id: UUID, delta: String, timestamp: Date)

    /// Agent response text final (complete)
    case agentTextFinal(id: UUID, text: String, timestamp: Date)

    // MARK: - Tool Events

    /// Agent started a tool call (e.g., checking balance)
    case toolCallStarted(id: UUID, name: String, timestamp: Date)

    /// Agent finished a tool call with optional summary
    case toolCallFinished(id: UUID, name: String, summary: String?, timestamp: Date)

    // MARK: - System Events

    /// System status message (connected, reconnected, paused, etc.)
    case systemStatus(id: UUID, message: String, timestamp: Date)

    /// Error event
    case error(id: UUID, message: String, timestamp: Date)

    // MARK: - Identifiable

    var id: UUID {
        switch self {
        case .userText(let id, _, _),
             .userSpeechDelta(let id, _, _),
             .userSpeechFinal(let id, _, _),
             .agentTextDelta(let id, _, _),
             .agentTextFinal(let id, _, _),
             .toolCallStarted(let id, _, _),
             .toolCallFinished(let id, _, _, _),
             .systemStatus(let id, _, _),
             .error(let id, _, _):
            return id
        }
    }

    var timestamp: Date {
        switch self {
        case .userText(_, _, let timestamp),
             .userSpeechDelta(_, _, let timestamp),
             .userSpeechFinal(_, _, let timestamp),
             .agentTextDelta(_, _, let timestamp),
             .agentTextFinal(_, _, let timestamp),
             .toolCallStarted(_, _, let timestamp),
             .toolCallFinished(_, _, _, let timestamp),
             .systemStatus(_, _, let timestamp),
             .error(_, _, let timestamp):
            return timestamp
        }
    }
}

// MARK: - Event Type Helpers

extension ConversationEvent {
    /// Whether this is a delta (streaming) event
    var isDelta: Bool {
        switch self {
        case .userSpeechDelta, .agentTextDelta:
            return true
        default:
            return false
        }
    }

    /// Whether this is a final (complete) event
    var isFinal: Bool {
        switch self {
        case .userText, .userSpeechFinal, .agentTextFinal:
            return true
        default:
            return false
        }
    }

    /// Whether this is a user event
    var isUserEvent: Bool {
        switch self {
        case .userText, .userSpeechDelta, .userSpeechFinal:
            return true
        default:
            return false
        }
    }

    /// Whether this is an agent event
    var isAgentEvent: Bool {
        switch self {
        case .agentTextDelta, .agentTextFinal:
            return true
        default:
            return false
        }
    }

    /// Whether this is a system event
    var isSystemEvent: Bool {
        switch self {
        case .systemStatus, .error:
            return true
        default:
            return false
        }
    }

    /// Whether this is a tool event
    var isToolEvent: Bool {
        switch self {
        case .toolCallStarted, .toolCallFinished:
            return true
        default:
            return false
        }
    }

    /// The text content of the event (if applicable)
    var textContent: String? {
        switch self {
        case .userText(_, let text, _),
             .userSpeechDelta(_, let text, _),
             .userSpeechFinal(_, let text, _),
             .agentTextDelta(_, let text, _),
             .agentTextFinal(_, let text, _),
             .systemStatus(_, let text, _),
             .error(_, let text, _):
            return text
        case .toolCallStarted(_, let name, _):
            return name
        case .toolCallFinished(_, let name, let summary, _):
            return summary ?? name
        }
    }
}

// MARK: - Factory Methods

extension ConversationEvent {
    /// Create a user text message event
    static func userText(_ text: String) -> ConversationEvent {
        .userText(id: UUID(), text: text, timestamp: Date())
    }

    /// Create an agent text delta event
    static func agentDelta(_ delta: String, id: UUID) -> ConversationEvent {
        .agentTextDelta(id: id, delta: delta, timestamp: Date())
    }

    /// Create an agent text final event
    static func agentFinal(_ text: String, id: UUID) -> ConversationEvent {
        .agentTextFinal(id: id, text: text, timestamp: Date())
    }

    /// Create a system status event
    static func status(_ message: String) -> ConversationEvent {
        .systemStatus(id: UUID(), message: message, timestamp: Date())
    }

    /// Create an error event
    static func errorEvent(_ message: String) -> ConversationEvent {
        .error(id: UUID(), message: message, timestamp: Date())
    }
}
