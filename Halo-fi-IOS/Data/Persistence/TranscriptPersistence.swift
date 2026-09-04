//
//  TranscriptPersistence.swift
//  Halo-fi-IOS
//
//  Conversation history on the phone: a list of sessions (title, dates,
//  entries), user-scoped in UserDefaults like LinkedItemsPersistence.
//  A new session starts on every launch; older ones are kept for
//  "Previous conversations" and can be resumed. Capped at 30 sessions of
//  200 finished entries. Transcript lines can carry balances, so the
//  whole store is cleared on sign-out.
//

import Foundation

struct ConversationSession: Codable, Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    var updatedAt: Date
    var entries: [TranscriptEntry]

    /// First thing the user said, or a date-based fallback.
    var title: String {
        if let first = entries.first(where: { $0.speaker == .user })?.text.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            return first.count > 60 ? String(first.prefix(57)) + "…" : first
        }
        return "Conversation"
    }
}

final class TranscriptPersistence {
    let userId: String
    private let defaults = UserDefaults.standard
    private let keyPrefix = "conversation_sessions_v2_"
    private let legacyPrefix = "conversation_transcript_v1_"
    private let maxSessions = 30
    private let maxEntries = 200

    init(userId: String) {
        self.userId = userId
        // Drop the pre-sessions single-thread key if it is still around.
        defaults.removeObject(forKey: legacyPrefix + userId)
    }

    private var key: String { keyPrefix + userId }

    func loadSessions() -> [ConversationSession] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([ConversationSession].self, from: data)
        } catch {
            Logger.warning("TranscriptPersistence: decode failed, clearing stale history")
            defaults.removeObject(forKey: key)
            return []
        }
    }

    func upsert(_ session: ConversationSession) {
        var sessions = loadSessions().filter { $0.id != session.id }
        var trimmed = session
        trimmed.entries = Array(session.entries.suffix(maxEntries))
        sessions.insert(trimmed, at: 0)
        sessions.sort { $0.updatedAt > $1.updatedAt }
        save(Array(sessions.prefix(maxSessions)))
    }

    func delete(id: UUID) {
        save(loadSessions().filter { $0.id != id })
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func save(_ sessions: [ConversationSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else {
            Logger.error("TranscriptPersistence: encode failed")
            return
        }
        defaults.set(data, forKey: key)
    }
}
