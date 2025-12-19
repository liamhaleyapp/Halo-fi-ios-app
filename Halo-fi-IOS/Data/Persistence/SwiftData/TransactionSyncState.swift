//
//  TransactionSyncState.swift
//  Halo-fi-IOS
//
//  SwiftData model for tracking transaction sync state per Plaid item.
//  Stores cursor for future incremental sync and freshness timestamps.
//

import Foundation
import SwiftData

@Model
final class TransactionSyncState {
    // MARK: - Primary Key

    /// Composite key: {userId}_{plaidItemId}
    @Attribute(.unique) var compositeId: String

    // MARK: - Identification

    /// User this sync state belongs to
    var userId: String

    /// Plaid item ID this state tracks
    var plaidItemId: String

    // MARK: - Sync Cursor (for future incremental sync)

    /// Cursor returned from last sync - use for incremental updates when backend supports it
    var cursor: String?

    /// Whether there are more transactions to fetch
    var hasMore: Bool

    // MARK: - Data Freshness Tracking

    /// When we last did a full sync (fetched all 2 years of history)
    var lastFullSyncAt: Date?

    /// When we last synced recent transactions (e.g., last 30 days)
    var lastRecentSyncAt: Date?

    /// Total number of transactions stored for this item
    var totalTransactionCount: Int

    // MARK: - Initialization

    init(userId: String, plaidItemId: String) {
        self.compositeId = "\(userId)_\(plaidItemId)"
        self.userId = userId
        self.plaidItemId = plaidItemId
        self.cursor = nil
        self.hasMore = true
        self.lastFullSyncAt = nil
        self.lastRecentSyncAt = nil
        self.totalTransactionCount = 0
    }

    // MARK: - Freshness Checks

    /// Whether a full sync is needed (never synced or >24h since last full sync)
    var needsFullSync: Bool {
        guard let lastFull = lastFullSyncAt else { return true }
        let hoursSinceFullSync = Date().timeIntervalSince(lastFull) / 3600
        return hoursSinceFullSync > 24
    }

    /// Whether a recent sync is needed (>5min since last sync)
    var needsRecentSync: Bool {
        guard let lastRecent = lastRecentSyncAt else { return true }
        let minutesSinceRecentSync = Date().timeIntervalSince(lastRecent) / 60
        return minutesSinceRecentSync > 5
    }

    // MARK: - Update Methods

    /// Mark that a full sync was completed
    func markFullSyncComplete(transactionCount: Int, cursor: String?, hasMore: Bool) {
        self.lastFullSyncAt = Date()
        self.lastRecentSyncAt = Date()
        self.totalTransactionCount = transactionCount
        self.cursor = cursor
        self.hasMore = hasMore
    }

    /// Mark that a recent sync was completed
    func markRecentSyncComplete(cursor: String?, hasMore: Bool) {
        self.lastRecentSyncAt = Date()
        self.cursor = cursor
        self.hasMore = hasMore
    }
}
