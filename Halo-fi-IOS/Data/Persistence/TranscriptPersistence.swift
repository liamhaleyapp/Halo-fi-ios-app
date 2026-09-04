//
//  TranscriptPersistence.swift
//  Halo-fi-IOS
//
//  WP7 — the chat thread survives app launches. UserDefaults with a
//  user-scoped key (same shape as LinkedItemsPersistence); capped at the
//  last 200 finished entries. Transcript lines can carry balances, so the
//  thread is cleared on logout with the rest of the user's local data.
//

import Foundation

final class TranscriptPersistence {
    let userId: String
    private let defaults = UserDefaults.standard
    private let keyPrefix = "conversation_transcript_v1_"
    private let maxEntries = 200

    init(userId: String) {
        self.userId = userId
    }

    private var key: String { keyPrefix + userId }

    func save(_ entries: [TranscriptEntry]) {
        let tail = Array(entries.suffix(maxEntries))
        guard let data = try? JSONEncoder().encode(tail) else {
            Logger.error("TranscriptPersistence: encode failed")
            return
        }
        defaults.set(data, forKey: key)
    }

    func load() -> [TranscriptEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([TranscriptEntry].self, from: data)
        } catch {
            Logger.warning("TranscriptPersistence: decode failed, clearing stale thread")
            defaults.removeObject(forKey: key)
            return []
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
