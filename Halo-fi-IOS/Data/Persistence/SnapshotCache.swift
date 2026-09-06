//
//  SnapshotCache.swift
//  Halo-fi-IOS
//
//  The last good snapshot, per user, so a cold launch draws real numbers
//  immediately instead of "$0 across 0 accounts" for the seconds the first
//  fetch takes (Liam, 2026-09-05). JSON in UserDefaults under user-scoped
//  keys; cleared on sign-out. Never a source of truth: every reader
//  refreshes right after hydrating.
//

import Foundation

enum SnapshotCache {
    private static let defaults = UserDefaults.standard
    private static let userKey = "snapshot_cache_user"

    /// The user whose snapshot is on disk (set on configure, cleared on sign-out).
    static var currentUserId: String? {
        get { defaults.string(forKey: userKey) }
        set { defaults.set(newValue, forKey: userKey) }
    }

    static func save<T: Encodable>(_ value: T, key: String, userId: String? = currentUserId) {
        guard let userId, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: "snapshot_\(key)_\(userId)")
    }

    static func load<T: Decodable>(_ type: T.Type, key: String, userId: String? = currentUserId) -> T? {
        guard let userId, let data = defaults.data(forKey: "snapshot_\(key)_\(userId)") else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func clear(userId: String) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("snapshot_") && key.hasSuffix("_\(userId)") {
            defaults.removeObject(forKey: key)
        }
        if currentUserId == userId { defaults.removeObject(forKey: userKey) }
    }
}
