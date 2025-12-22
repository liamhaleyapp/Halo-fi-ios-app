//
//  AccountPersistence.swift
//  Halo-fi-IOS
//
//  SwiftData implementation of account persistence.
//  Enables instant display of cached accounts with background refresh.
//

import Foundation
import SwiftData

/// SwiftData-based implementation of account persistence
@MainActor
final class AccountPersistence: AccountPersistenceProtocol, @unchecked Sendable {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Loading

    func loadAccounts(for userId: String, plaidItemId: String) async -> [BankAccount] {
        let context = modelContainer.mainContext

        do {
            let predicate = #Predicate<PersistedAccount> {
                $0.userId == userId &&
                $0.plaidItemId == plaidItemId
            }
            let descriptor = FetchDescriptor<PersistedAccount>(predicate: predicate)

            let persisted = try context.fetch(descriptor)
            let accounts = persisted.compactMap { $0.toBankAccount() }
            Logger.debug("AccountPersistence: Loaded \(accounts.count) accounts for item \(plaidItemId)")
            return accounts
        } catch {
            Logger.error("AccountPersistence: Failed to load accounts: \(error.localizedDescription)")
            return []
        }
    }

    func loadAllAccounts(for userId: String) async -> [String: [BankAccount]] {
        let context = modelContainer.mainContext

        do {
            let predicate = #Predicate<PersistedAccount> { $0.userId == userId }
            let descriptor = FetchDescriptor<PersistedAccount>(predicate: predicate)

            let persisted = try context.fetch(descriptor)
            var grouped: [String: [BankAccount]] = [:]

            // Debug: Check for duplicate compositeIds
            var seenCompositeIds = Set<String>()
            for item in persisted {
                if seenCompositeIds.contains(item.compositeId) {
                    Logger.warning("AccountPersistence: DUPLICATE compositeId found: \(item.compositeId)")
                }
                seenCompositeIds.insert(item.compositeId)

                if let account = item.toBankAccount() {
                    grouped[item.plaidItemId, default: []].append(account)
                }
            }

            Logger.debug("AccountPersistence: Loaded \(persisted.count) persisted rows, \(seenCompositeIds.count) unique, across \(grouped.count) items")
            for (itemId, accounts) in grouped {
                Logger.debug("AccountPersistence: Item \(itemId.prefix(8))... -> \(accounts.count) accounts")
            }
            return grouped
        } catch {
            Logger.error("AccountPersistence: Failed to load all accounts: \(error.localizedDescription)")
            return [:]
        }
    }

    // MARK: - Write Operations

    func saveAccounts(_ accounts: [BankAccount], for userId: String, plaidItemId: String) async {
        let context = modelContainer.mainContext

        // Build a set of incoming account IDs for delete-missing logic
        let incomingAccountIds = Set(accounts.map { $0.idAccount })

        // Fetch existing persisted accounts for this user+item
        let predicate = #Predicate<PersistedAccount> {
            $0.userId == userId &&
            $0.plaidItemId == plaidItemId
        }
        let descriptor = FetchDescriptor<PersistedAccount>(predicate: predicate)

        do {
            let existing = try context.fetch(descriptor)
            var existingByAccountId: [String: PersistedAccount] = [:]
            for item in existing {
                existingByAccountId[item.accountId] = item
            }

            // Upsert incoming accounts
            for account in accounts {
                if let persisted = existingByAccountId[account.idAccount] {
                    // Update existing
                    persisted.update(from: account)
                } else {
                    // Insert new
                    let persisted = PersistedAccount(
                        from: account,
                        userId: userId,
                        plaidItemId: plaidItemId
                    )
                    context.insert(persisted)
                }
            }

            // Delete accounts that no longer exist (closed/removed)
            for (accountId, persisted) in existingByAccountId where !incomingAccountIds.contains(accountId) {
                context.delete(persisted)
                Logger.debug("AccountPersistence: Deleted removed account \(accountId)")
            }

            try context.save()
            Logger.debug("AccountPersistence: Saved \(accounts.count) accounts for item \(plaidItemId)")
        } catch {
            Logger.error("AccountPersistence: Failed to save accounts: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync State

    func needsRefresh(for userId: String, plaidItemId: String) async -> Bool {
        guard let state = await getSyncState(for: userId, plaidItemId: plaidItemId) else {
            return true  // No state means we've never synced
        }
        return state.needsRefresh
    }

    func markRefreshComplete(for userId: String, plaidItemId: String) async {
        let context = modelContainer.mainContext
        let compositeId = "\(userId)_\(plaidItemId)"

        let predicate = #Predicate<AccountSyncState> { $0.compositeId == compositeId }
        let descriptor = FetchDescriptor<AccountSyncState>(predicate: predicate)

        do {
            let existing = try context.fetch(descriptor)

            // Count accounts for this item
            let accountPredicate = #Predicate<PersistedAccount> {
                $0.userId == userId &&
                $0.plaidItemId == plaidItemId
            }
            let accountDescriptor = FetchDescriptor<PersistedAccount>(predicate: accountPredicate)
            let accountCount = try context.fetchCount(accountDescriptor)

            if let state = existing.first {
                state.markRefreshComplete(accountCount: accountCount)
            } else {
                let state = AccountSyncState(userId: userId, plaidItemId: plaidItemId)
                state.markRefreshComplete(accountCount: accountCount)
                context.insert(state)
            }

            try context.save()
            Logger.debug("AccountPersistence: Marked refresh complete for item \(plaidItemId)")
        } catch {
            Logger.error("AccountPersistence: Failed to mark refresh complete: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func getSyncState(for userId: String, plaidItemId: String) async -> AccountSyncState? {
        let context = modelContainer.mainContext
        let compositeId = "\(userId)_\(plaidItemId)"

        let predicate = #Predicate<AccountSyncState> { $0.compositeId == compositeId }
        let descriptor = FetchDescriptor<AccountSyncState>(predicate: predicate)

        do {
            let existing = try context.fetch(descriptor)
            return existing.first
        } catch {
            Logger.error("AccountPersistence: Failed to get sync state: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Clear Operations

    func clearAccounts(for userId: String) async {
        let context = modelContainer.mainContext

        do {
            // Clear accounts
            let accountPredicate = #Predicate<PersistedAccount> { $0.userId == userId }
            try context.delete(model: PersistedAccount.self, where: accountPredicate)

            // Clear sync states
            let statePredicate = #Predicate<AccountSyncState> { $0.userId == userId }
            try context.delete(model: AccountSyncState.self, where: statePredicate)

            try context.save()
            Logger.info("AccountPersistence: Cleared all accounts for user")
        } catch {
            Logger.error("AccountPersistence: Failed to clear accounts: \(error.localizedDescription)")
        }
    }

    func clearAll() async {
        let context = modelContainer.mainContext

        do {
            try context.delete(model: PersistedAccount.self)
            try context.delete(model: AccountSyncState.self)
            try context.save()
            Logger.info("AccountPersistence: Cleared all persisted account data")
        } catch {
            Logger.error("AccountPersistence: Failed to clear all data: \(error.localizedDescription)")
        }
    }
}
