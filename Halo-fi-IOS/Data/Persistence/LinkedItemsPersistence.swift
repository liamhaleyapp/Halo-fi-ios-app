//
//  LinkedItemsPersistence.swift
//  Halo-fi-IOS
//
//  Handles persistence of linked Plaid items per user.
//  Uses UserDefaults with user-scoped keys to prevent cross-user data leakage.
//

import Foundation

final class LinkedItemsPersistence {
    private let defaults = UserDefaults.standard
    private let itemsKeyPrefix = "linked_plaid_items_"
    private let refreshKeyPrefix = "last_bank_refresh_at_"

    // MARK: - Linked Items

    func save(_ items: [ConnectedItem], for userId: String) {
        let key = itemsKeyPrefix + userId
        guard let data = try? JSONEncoder().encode(items) else {
            Logger.error("LinkedItemsPersistence: Failed to encode linked items")
            return
        }
        defaults.set(data, forKey: key)
        Logger.debug("LinkedItemsPersistence: Saved \(items.count) linked items for user")
    }

    func load(for userId: String) -> [ConnectedItem]? {
        let key = itemsKeyPrefix + userId
        guard let data = defaults.data(forKey: key) else { return nil }

        do {
            return try JSONDecoder().decode([ConnectedItem].self, from: data)
        } catch {
            // Decode failed (schema changed?) - clear stale data and return nil
            Logger.warning("LinkedItemsPersistence: Failed to decode linked items, clearing stale data")
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    func clear(for userId: String) {
        let itemsKey = itemsKeyPrefix + userId
        let refreshKey = refreshKeyPrefix + userId
        defaults.removeObject(forKey: itemsKey)
        defaults.removeObject(forKey: refreshKey)
        Logger.debug("LinkedItemsPersistence: Cleared linked items and refresh timestamp for user")
    }

    // MARK: - Last Refresh Timestamp (per-user)

    func getLastRefreshAt(for userId: String) -> Date? {
        let key = refreshKeyPrefix + userId
        let interval = defaults.double(forKey: key)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    func setLastRefreshAt(_ date: Date, for userId: String) {
        let key = refreshKeyPrefix + userId
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }

    // MARK: - Debug/Testing

    /// Clear ALL users' data (for testing/debug only)
    func clearAll() {
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys where key.hasPrefix(itemsKeyPrefix) || key.hasPrefix(refreshKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        Logger.debug("LinkedItemsPersistence: Cleared all persisted data")
    }
}
