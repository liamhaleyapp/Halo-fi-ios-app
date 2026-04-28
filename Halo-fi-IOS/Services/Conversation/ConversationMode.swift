//
//  ConversationMode.swift
//  Halo-fi-IOS
//
//  Two ways the user can drive a voice conversation:
//
//    .pushToTalk — Tap the mic to start speaking, tap again to stop
//                  and submit. Each turn is explicit.
//
//    .handsFree  — Conversation auto-flows: Halo speaks, mic auto-
//                  unmutes, ElevenLabs server-side VAD detects the
//                  end of the user's utterance, response plays, and
//                  the loop repeats. The big mic button toggles mute
//                  instead of starting / stopping turns; an explicit
//                  End button tears down the conversation.
//
//  Persisted on the user's Preferences row (column Conversation_Mode)
//  and mirrored locally via @AppStorage("conversationMode") so the
//  view layer doesn't need to round-trip the API for each render.
//

import Foundation

enum ConversationMode: String, CaseIterable, Sendable {
    case pushToTalk = "push_to_talk"
    case handsFree = "hands_free"

    /// Defensive fallback used when the backend or AppStorage returns
    /// a value we don't recognize. We default to push-to-talk because
    /// that's the historical behavior — users who never opted in
    /// should see no change.
    static func from(_ raw: String?) -> ConversationMode {
        guard let raw, let mode = ConversationMode(rawValue: raw) else {
            return .pushToTalk
        }
        return mode
    }
}
