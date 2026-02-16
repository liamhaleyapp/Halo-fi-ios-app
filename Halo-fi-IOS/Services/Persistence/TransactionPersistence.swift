//
//  TransactionPersistence.swift
//  Halo-fi-IOS
//
//  SwiftData implementation of transaction persistence.
//  Enables instant display of cached transactions with background refresh.
//

import Foundation
import SwiftData

/// SwiftData-based implementation of transaction persistence
@MainActor
final class TransactionPersistence: TransactionPersistenceProtocol, @unchecked Sendable {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Paginated Loading

    func loadTransactions(
        for userId: String,
        accountId: String,
        limit: Int,
        before: Date?
    ) async -> [Transaction] {
        let context = modelContainer.mainContext

        do {
            var descriptor: FetchDescriptor<PersistedTransaction>

            if let beforeDate = before {
                let predicate = #Predicate<PersistedTransaction> {
                    $0.userId == userId &&
                    $0.plaidAccountId == accountId &&
                    $0.transactionDate < beforeDate
                }
                descriptor = FetchDescriptor<PersistedTransaction>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
                )
            } else {
                let predicate = #Predicate<PersistedTransaction> {
                    $0.userId == userId &&
                    $0.plaidAccountId == accountId
                }
                descriptor = FetchDescriptor<PersistedTransaction>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
                )
            }

            descriptor.fetchLimit = limit

            let persisted = try context.fetch(descriptor)
            Logger.debug("TransactionPersistence: Loaded \(persisted.count) transactions for account \(accountId)")
            return persisted.map { $0.toTransaction() }
        } catch {
            Logger.error("TransactionPersistence: Failed to load transactions: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Bulk Loading

    func loadAllTransactions(for userId: String, itemId: String) async -> [Transaction] {
        let context = modelContainer.mainContext

        do {
            // Note: plaidItemId field stores the itemId value
            let predicate = #Predicate<PersistedTransaction> {
                $0.userId == userId &&
                $0.plaidItemId == itemId
            }
            let descriptor = FetchDescriptor<PersistedTransaction>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
            )

            let persisted = try context.fetch(descriptor)
            Logger.debug("TransactionPersistence: Loaded all \(persisted.count) transactions for item \(itemId)")
            return persisted.map { $0.toTransaction() }
        } catch {
            Logger.error("TransactionPersistence: Failed to load all transactions: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Write Operations

    func saveTransactions(_ transactions: [Transaction], for userId: String, itemId: String) async {
        let context = modelContainer.mainContext

        for transaction in transactions {
            let compositeId = "\(userId)_\(transaction.idTransaction)"

            // Check if transaction already exists
            let predicate = #Predicate<PersistedTransaction> { $0.compositeId == compositeId }
            let descriptor = FetchDescriptor<PersistedTransaction>(predicate: predicate)

            do {
                let existing = try context.fetch(descriptor)
                if let persisted = existing.first {
                    // Update existing transaction
                    persisted.update(from: transaction)
                } else {
                    // Insert new transaction (plaidItemId field stores itemId)
                    let persisted = PersistedTransaction(
                        from: transaction,
                        userId: userId,
                        plaidItemId: itemId,
                        plaidAccountId: transaction.accountId
                    )
                    context.insert(persisted)
                }
            } catch {
                Logger.error("TransactionPersistence: Failed to save transaction \(transaction.idTransaction): \(error.localizedDescription)")
            }
        }

        do {
            try context.save()
            Logger.debug("TransactionPersistence: Saved \(transactions.count) transactions for item \(itemId)")
        } catch {
            Logger.error("TransactionPersistence: Failed to commit transaction save: \(error.localizedDescription)")
        }
    }

    func updateSyncState(cursor: String?, hasMore: Bool, for userId: String, itemId: String) async {
        let context = modelContainer.mainContext
        let compositeId = "\(userId)_\(itemId)"

        // Note: plaidItemId field stores the itemId value
        let predicate = #Predicate<TransactionSyncState> { $0.compositeId == compositeId }
        let descriptor = FetchDescriptor<TransactionSyncState>(predicate: predicate)

        do {
            let existing = try context.fetch(descriptor)
            if let state = existing.first {
                state.cursor = cursor
                state.hasMore = hasMore
            } else {
                let state = TransactionSyncState(userId: userId, plaidItemId: itemId)
                state.cursor = cursor
                state.hasMore = hasMore
                context.insert(state)
            }
            try context.save()
        } catch {
            Logger.error("TransactionPersistence: Failed to update sync state: \(error.localizedDescription)")
        }
    }

    func markFullSyncComplete(for userId: String, itemId: String) async {
        let context = modelContainer.mainContext
        let compositeId = "\(userId)_\(itemId)"

        let predicate = #Predicate<TransactionSyncState> { $0.compositeId == compositeId }
        let descriptor = FetchDescriptor<TransactionSyncState>(predicate: predicate)

        do {
            let existing = try context.fetch(descriptor)
            if let state = existing.first {
                state.lastFullSyncAt = Date()
                state.lastRecentSyncAt = Date()
            } else {
                let state = TransactionSyncState(userId: userId, plaidItemId: itemId)
                state.lastFullSyncAt = Date()
                state.lastRecentSyncAt = Date()
                context.insert(state)
            }
            try context.save()
            Logger.debug("TransactionPersistence: Marked full sync complete for item \(itemId)")
        } catch {
            Logger.error("TransactionPersistence: Failed to mark full sync complete: \(error.localizedDescription)")
        }
    }

    func markRecentSyncComplete(for userId: String, itemId: String) async {
        let context = modelContainer.mainContext
        let compositeId = "\(userId)_\(itemId)"

        let predicate = #Predicate<TransactionSyncState> { $0.compositeId == compositeId }
        let descriptor = FetchDescriptor<TransactionSyncState>(predicate: predicate)

        do {
            let existing = try context.fetch(descriptor)
            if let state = existing.first {
                state.lastRecentSyncAt = Date()
            } else {
                let state = TransactionSyncState(userId: userId, plaidItemId: itemId)
                state.lastRecentSyncAt = Date()
                context.insert(state)
            }
            try context.save()
            Logger.debug("TransactionPersistence: Marked recent sync complete for item \(itemId)")
        } catch {
            Logger.error("TransactionPersistence: Failed to mark recent sync complete: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync State Queries

    func getSyncState(for userId: String, itemId: String) async -> SyncStateInfo? {
        let context = modelContainer.mainContext
        let compositeId = "\(userId)_\(itemId)"

        let predicate = #Predicate<TransactionSyncState> { $0.compositeId == compositeId }
        let descriptor = FetchDescriptor<TransactionSyncState>(predicate: predicate)

        do {
            let existing = try context.fetch(descriptor)
            return existing.first?.toSyncStateInfo()
        } catch {
            Logger.error("TransactionPersistence: Failed to get sync state: \(error.localizedDescription)")
            return nil
        }
    }

    func needsFullSync(for userId: String, itemId: String) async -> Bool {
        guard let state = await getSyncState(for: userId, itemId: itemId) else {
            return true  // No state means we've never synced
        }
        return state.needsFullSync
    }

    func needsRecentSync(for userId: String, itemId: String) async -> Bool {
        guard let state = await getSyncState(for: userId, itemId: itemId) else {
            return true  // No state means we've never synced
        }
        return state.needsRecentSync
    }

    // MARK: - Clear Operations

    func clearTransactions(for userId: String) async {
        let context = modelContainer.mainContext

        do {
            // Clear transactions
            let txnPredicate = #Predicate<PersistedTransaction> { $0.userId == userId }
            try context.delete(model: PersistedTransaction.self, where: txnPredicate)

            // Clear sync states
            let statePredicate = #Predicate<TransactionSyncState> { $0.userId == userId }
            try context.delete(model: TransactionSyncState.self, where: statePredicate)

            try context.save()
            Logger.info("TransactionPersistence: Cleared all transactions for user \(userId)")
        } catch {
            Logger.error("TransactionPersistence: Failed to clear transactions: \(error.localizedDescription)")
        }
    }

    func clearTransactions(for userId: String, itemId: String) async {
        let context = modelContainer.mainContext

        do {
            // Clear transactions for this specific item (plaidItemId field stores itemId)
            let txnPredicate = #Predicate<PersistedTransaction> {
                $0.userId == userId && $0.plaidItemId == itemId
            }
            let txnDescriptor = FetchDescriptor<PersistedTransaction>(predicate: txnPredicate)
            let transactions = try context.fetch(txnDescriptor)
            for transaction in transactions {
                context.delete(transaction)
            }

            // Clear sync state for this item
            let syncPredicate = #Predicate<TransactionSyncState> {
                $0.userId == userId && $0.plaidItemId == itemId
            }
            let syncDescriptor = FetchDescriptor<TransactionSyncState>(predicate: syncPredicate)
            let syncStates = try context.fetch(syncDescriptor)
            for state in syncStates {
                context.delete(state)
            }

            try context.save()
            Logger.info("TransactionPersistence: Cleared transactions for itemId: \(itemId)")
        } catch {
            Logger.error("TransactionPersistence: Failed to clear transactions for item: \(error.localizedDescription)")
        }
    }

    func clearAll() async {
        let context = modelContainer.mainContext

        do {
            try context.delete(model: PersistedTransaction.self)
            try context.delete(model: TransactionSyncState.self)
            try context.save()
            Logger.info("TransactionPersistence: Cleared all persisted transaction data")
        } catch {
            Logger.error("TransactionPersistence: Failed to clear all data: \(error.localizedDescription)")
        }
    }
}
