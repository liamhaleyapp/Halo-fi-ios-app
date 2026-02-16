//
//  AccountPersistenceProtocol.swift
//  Halo-fi-IOS
//
//  Protocol for account persistence operations.
//  Enables testing with mock implementations.
//

import Foundation

/// Protocol defining account persistence operations
protocol AccountPersistenceProtocol: Sendable {
    // MARK: - Loading

    /// Load accounts for a specific bank item
    /// - Parameters:
    ///   - userId: User ID for isolation
    ///   - itemId: Internal bank item UUID to load accounts for
    /// - Returns: Array of accounts for this item
    func loadAccounts(for userId: String, itemId: String) async -> [BankAccount]

    /// Load all accounts for a user (across all items)
    /// - Parameter userId: User ID for isolation
    /// - Returns: Dictionary of itemId -> accounts
    func loadAllAccounts(for userId: String) async -> [String: [BankAccount]]

    // MARK: - Write Operations

    /// Save accounts to persistent storage
    /// - Parameters:
    ///   - accounts: Accounts to save (will upsert based on ID, delete missing)
    ///   - userId: User ID for isolation
    ///   - itemId: Internal bank item UUID these accounts belong to
    func saveAccounts(_ accounts: [BankAccount], for userId: String, itemId: String) async

    // MARK: - Sync State

    /// Check if accounts need refreshing (>5min since last refresh)
    func needsRefresh(for userId: String, itemId: String) async -> Bool

    /// Mark that a refresh was completed for an item
    func markRefreshComplete(for userId: String, itemId: String) async

    // MARK: - Clear Operations

    /// Clear all accounts for a user (e.g., on sign out)
    func clearAccounts(for userId: String) async

    /// Clear accounts for a specific bank item (e.g., on disconnect)
    func clearAccounts(for userId: String, itemId: String) async

    /// Clear all persisted data
    func clearAll() async
}
