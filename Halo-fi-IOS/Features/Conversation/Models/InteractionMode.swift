//
//  InteractionMode.swift
//  Halo-fi-IOS
//
//  Represents the user's current input mode preference.
//  Separate from ConversationState which handles lifecycle.
//

import Foundation

/// User interaction mode - determines UI layout and input focus
enum InteractionMode: Equatable {
    /// Voice-first mode with large mic button focused
    case voice

    /// Text mode with keyboard focused
    case text
}

// MARK: - Display Helpers

extension InteractionMode {
    /// Label for the mode toggle button
    var toggleButtonLabel: String {
        switch self {
        case .voice:
            return "Type instead"
        case .text:
            return "Switch to voice"
        }
    }

    /// Icon name for the mode toggle button
    var toggleButtonIcon: String {
        switch self {
        case .voice:
            return "keyboard"
        case .text:
            return "mic.fill"
        }
    }

    /// VoiceOver hint for the mode toggle
    var toggleButtonHint: String {
        switch self {
        case .voice:
            return "Double tap to switch to typing"
        case .text:
            return "Double tap to switch to voice input"
        }
    }
}
