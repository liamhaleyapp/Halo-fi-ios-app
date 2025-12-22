//
//  AccountSyncState.swift
//  Halo-fi-IOS
//
//  SwiftData model for tracking account sync state per Plaid item.
//  Stores freshness timestamp for stale-while-revalidate pattern.
//

import Foundation
import SwiftData

@Model
final class AccountSyncState {
    // MARK: - Primary Key

    /// Composite key: {userId}_{plaidItemId}
    @Attribute(.unique) var compositeId: String

    // MARK: - Identification

    /// User this sync state belongs to
    var userId: String

    /// Plaid item ID this state tracks
    var plaidItemId: String

    // MARK: - Data Freshness Tracking

    /// When we last refreshed accounts for this item
    var lastRefreshAt: Date?

    /// Number of accounts stored for this item
    var accountCount: Int

    // MARK: - Constants

    /// Refresh threshold in seconds (5 minutes, matching transaction sync)
    private static let refreshThresholdSeconds: TimeInterval = 300

    // MARK: - Initialization

    init(userId: String, plaidItemId: String) {
        self.compositeId = "\(userId)_\(plaidItemId)"
        self.userId = userId
        self.plaidItemId = plaidItemId
        self.lastRefreshAt = nil
        self.accountCount = 0
    }

    // MARK: - Freshness Check

    /// Whether a refresh is needed (never refreshed or >5min since last refresh)
    var needsRefresh: Bool {
        guard let lastRefresh = lastRefreshAt else { return true }
        let secondsSinceRefresh = Date().timeIntervalSince(lastRefresh)
        return secondsSinceRefresh > Self.refreshThresholdSeconds
    }

    // MARK: - Update Methods

    /// Mark that a refresh was completed
    func markRefreshComplete(accountCount: Int) {
        self.lastRefreshAt = Date()
        self.accountCount = accountCount
    }
}
