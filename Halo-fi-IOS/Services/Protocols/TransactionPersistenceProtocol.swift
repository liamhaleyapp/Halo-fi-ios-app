//
//  TransactionPersistenceProtocol.swift
//  Halo-fi-IOS
//
//  Protocol for transaction persistence operations.
//  Enables testing with mock implementations.
//

import Foundation

/// Protocol defining transaction persistence operations
protocol TransactionPersistenceProtocol: Sendable {
    // MARK: - Paginated Loading (Primary Use Case)

    /// Load transactions for a specific account with pagination
    /// - Parameters:
    ///   - userId: User ID for isolation
    ///   - accountId: Account to load transactions for
    ///   - limit: Maximum number of transactions to return
    ///   - before: Only return transactions before this date (for pagination)
    /// - Returns: Array of transactions sorted by date descending
    func loadTransactions(
        for userId: String,
        accountId: String,
        limit: Int,
        before: Date?
    ) async -> [Transaction]

    // MARK: - Bulk Loading (for initial cache population)

    /// Load all transactions for a bank item
    /// - Parameters:
    ///   - userId: User ID for isolation
    ///   - itemId: Internal bank item UUID to load transactions for
    /// - Returns: Array of all transactions for this item
    func loadAllTransactions(for userId: String, itemId: String) async -> [Transaction]

    // MARK: - Write Operations

    /// Save transactions to persistent storage
    /// - Parameters:
    ///   - transactions: Transactions to save (will upsert based on ID)
    ///   - userId: User ID for isolation
    ///   - itemId: Internal bank item UUID these transactions belong to
    func saveTransactions(_ transactions: [Transaction], for userId: String, itemId: String) async

    /// Update sync state with cursor and completion status
    /// - Parameters:
    ///   - cursor: Cursor for next sync (from API response)
    ///   - hasMore: Whether more transactions are available
    ///   - userId: User ID for isolation
    ///   - itemId: Internal bank item UUID this state belongs to
    func updateSyncState(cursor: String?, hasMore: Bool, for userId: String, itemId: String) async

    /// Mark that a full sync was completed for an item
    func markFullSyncComplete(for userId: String, itemId: String) async

    /// Mark that a recent sync was completed for an item
    func markRecentSyncComplete(for userId: String, itemId: String) async

    // MARK: - Sync State Queries

    /// Get the sync state for a bank item
    func getSyncState(for userId: String, itemId: String) async -> SyncStateInfo?

    /// Check if a full sync is needed (never synced or >24h)
    func needsFullSync(for userId: String, itemId: String) async -> Bool

    /// Check if a recent sync is needed (>5min since last)
    func needsRecentSync(for userId: String, itemId: String) async -> Bool

    // MARK: - Clear Operations

    /// Clear all transactions for a user (e.g., on sign out)
    func clearTransactions(for userId: String) async

    /// Clear transactions for a specific bank item (e.g., on disconnect)
    func clearTransactions(for userId: String, itemId: String) async

    /// Clear all persisted data
    func clearAll() async
}
