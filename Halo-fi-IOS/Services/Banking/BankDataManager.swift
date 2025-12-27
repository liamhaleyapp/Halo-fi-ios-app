//
//  BankDataManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/5/25.
//

import Foundation
import SwiftUI

// swiftlint:disable type_body_length
@Observable
@MainActor
final class BankDataManager {
    // MARK: - State

    var accounts: [BankAccount]?
    var transactions: [Transaction]?
    var accountsSummary: BankAccountsResponse?

    /// Linked items (institutions) from Plaid - use mutation methods to modify
    private(set) var linkedItems: [ConnectedItem]?

    /// Accounts grouped by item ID - fetched on demand using GET /bank/{item_id}/account
    var accountsByItemId: [String: [BankAccount]] = [:]

    /// Transactions grouped by item ID - fetched on demand
    var transactionsByItemId: [String: [Transaction]] = [:]

    var isLoadingAccounts = false
    var isLoadingTransactions = false
    var isSyncing = false

    /// When transactions were last synced from the server (for "Updated X ago" display)
    var lastTransactionSyncAt: Date?

    var accountsError: BankError?
    var transactionsError: BankError?
    var syncError: BankError?

    // Cache management
    private var accountsLastFetched: Date?
    private var transactionsLastFetched: Date?
    private var transactionsCacheKey: String?

    // Cache TTL (Time To Live) - 5 minutes
    private let cacheTTL: TimeInterval = 300

    // Refresh threshold for auto-refresh on launch
    private let refreshThreshold: TimeInterval = 300

    // MARK: - Dependencies

    private let bankService: BankServiceProtocol
    private let persistence = LinkedItemsPersistence()
    private let transactionPersistence: TransactionPersistenceProtocol?
    private let accountPersistence: AccountPersistenceProtocol?
    private var currentUserId: String?

    /// In-flight account refresh tasks keyed by (userId, plaidItemId) to prevent refresh storms
    private var accountRefreshTasks: [String: Task<Void, Never>] = [:]

    /// In-flight guard for linked items fetch to prevent duplicate API calls
    private var linkedItemsFetchTask: Task<Void, Never>?

    /// In-flight guard for refresh to prevent duplicate refresh storms
    private var refreshTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a BankDataManager with optional persistence services
    /// - Parameters:
    ///   - bankService: Service for bank API calls
    ///   - transactionPersistence: Optional persistence for instant transaction display (nil disables caching)
    ///   - accountPersistence: Optional persistence for instant account display (nil disables caching)
    init(
        bankService: BankServiceProtocol = BankService.shared,
        transactionPersistence: TransactionPersistenceProtocol? = nil,
        accountPersistence: AccountPersistenceProtocol? = nil
    ) {
        self.bankService = bankService
        self.transactionPersistence = transactionPersistence
        self.accountPersistence = accountPersistence
    }

    // MARK: - User Session Management

    /// Call after auth resolves with valid user
    func configureForUser(userId: String) {
        currentUserId = userId

        Task { @MainActor in
            // 1. Restore linked items - return value for explicit ordering
            let restoredItems = restoreLinkedItemsSync()

            // 2. If persistence was empty, fetch from server
            if restoredItems.isEmpty {
                await fetchLinkedItemsFromServer()
            }

            // 3. Restore accounts from persistence
            await restoreAccounts()

            // 4. Refresh if stale (single network call, guarded)
            await refreshIfStale()

            // 5. Ensure accountsByItemId is populated
            rebuildAccountsByItemId()
        }
    }

    /// Synchronous restore that returns the result for explicit ordering
    /// Must run on MainActor since it mutates linkedItems
    private func restoreLinkedItemsSync() -> [ConnectedItem] {
        guard let userId = currentUserId else { return [] }

        if let items = persistence.load(for: userId), !items.isEmpty {
            linkedItems = items  // Set directly, don't re-persist
            Logger.info("BankDataManager: Restored \(items.count) linked items from persistence")
            return items
        }
        return []
    }

    /// Fetch linked items from server with in-flight guard
    /// Second callers await the same task instead of returning early
    private func fetchLinkedItemsFromServer() async {
        // If task already in-flight, await it instead of returning early
        if let task = linkedItemsFetchTask {
            await task.value
            return
        }

        linkedItemsFetchTask = Task {
            defer { linkedItemsFetchTask = nil }

            do {
                let response = try await bankService.getLinkedItems()

                // Map server items to ConnectedItem and apply userId
                var items = response.items.map { ConnectedItem(from: $0) }
                if let userId = currentUserId {
                    items = items.map { $0.withUserId(userId) }
                }

                guard !items.isEmpty else { return }

                // Extract embedded accounts from each item
                var embeddedAccountsByItemId: [String: [BankAccount]] = [:]
                for serverItem in response.items {
                    if let serverAccounts = serverItem.accounts, !serverAccounts.isEmpty {
                        let bankAccounts = serverAccounts.map { $0.toBankAccount(plaidItemId: serverItem.plaidItemId) }
                        embeddedAccountsByItemId[serverItem.plaidItemId] = bankAccounts
                    }
                }

                await MainActor.run {
                    setLinkedItems(items)  // Sets property + persists

                    // Populate accountsByItemId with embedded accounts
                    if !embeddedAccountsByItemId.isEmpty {
                        for (itemId, accounts) in embeddedAccountsByItemId {
                            accountsByItemId[itemId] = accounts
                        }
                        Logger.success("BankDataManager: Populated \(embeddedAccountsByItemId.count) items with \(embeddedAccountsByItemId.values.flatMap { $0 }.count) embedded accounts")
                    }
                }
                Logger.success("BankDataManager: Fetched \(items.count) linked items from server")
            } catch {
                Logger.error("BankDataManager: Failed to fetch linked items: \(error)")
                // Fallback: synthesize from accounts if available
                await synthesizeLinkedItemsFromAccountsIfNeeded()
            }
        }

        await linkedItemsFetchTask?.value
    }

    /// Fallback: If items endpoint fails but accounts exist, synthesize stubs
    private func synthesizeLinkedItemsFromAccountsIfNeeded() async {
        guard linkedItems?.isEmpty != false else { return }

        // Check BOTH accountsByItemId AND accounts property for fallback
        let allAccounts: [BankAccount]
        if !accountsByItemId.isEmpty {
            allAccounts = accountsByItemId.values.flatMap { $0 }
        } else if let accounts = accounts, !accounts.isEmpty {
            allAccounts = accounts
        } else {
            return  // No accounts to synthesize from
        }

        // Group by plaid_item_id and create stub ConnectedItems
        // Filter out accounts with nil plaidItemId
        let uniqueItemIds = Set(allAccounts.compactMap { $0.plaidItemId })
        let stubs = uniqueItemIds.map { plaidItemId -> ConnectedItem in
            ConnectedItem(
                institutionId: "",
                institutionName: "Unknown Institution",
                availableProducts: nil,
                itemId: "stub:\(plaidItemId)",  // Prefix to avoid collision with real IDs
                userId: currentUserId ?? "",
                plaidItemId: plaidItemId,
                isActive: true,
                lastSync: nil,
                createdAt: nil,
                updatedAt: nil
            )
        }

        if !stubs.isEmpty {
            await MainActor.run {
                setLinkedItems(stubs)
            }
            Logger.warning("BankDataManager: Synthesized \(stubs.count) linked items from accounts (fallback)")
        }
    }

    /// Rebuild accountsByItemId from accounts (always run to avoid stale state)
    private func rebuildAccountsByItemId() {
        if let accounts = accounts, !accounts.isEmpty {
            // Filter to only accounts with plaidItemId and group by it
            let accountsWithItemId = accounts.filter { $0.plaidItemId != nil }
            accountsByItemId = Dictionary(grouping: accountsWithItemId, by: { $0.plaidItemId! })
            Logger.debug("BankDataManager: Rebuilt accountsByItemId with \(accountsByItemId.count) items")
        }
    }

    private func restoreAccounts() async {
        guard let userId = currentUserId, let persistence = accountPersistence else { return }

        let accountsByItem = await persistence.loadAllAccounts(for: userId)
        if !accountsByItem.isEmpty {
            accountsByItemId = accountsByItem
            Logger.info("BankDataManager: Restored \(accountsByItem.values.flatMap { $0 }.count) accounts across \(accountsByItem.count) items")
            // Debug: Show breakdown per item
            for (itemId, accounts) in accountsByItem {
                Logger.debug("BankDataManager: Item \(itemId.prefix(8))... has \(accounts.count) accounts")
            }
        }
    }

    // MARK: - Linked Items Mutation Methods

    func setLinkedItems(_ items: [ConnectedItem]?) {
        guard let userId = currentUserId else {
            Logger.warning("BankDataManager: Cannot set linked items - no user configured")
            return
        }
        linkedItems = items
        if let items = items, !items.isEmpty {
            persistence.save(items, for: userId)
        } else {
            persistence.clear(for: userId)
        }
    }

    func addLinkedItem(_ item: ConnectedItem) {
        var current = linkedItems ?? []
        if !current.contains(where: { $0.plaidItemId == item.plaidItemId }) {
            current.append(item)
        }
        setLinkedItems(current)
    }

    func removeLinkedItem(plaidItemId: String) {
        guard var current = linkedItems else { return }
        current.removeAll { $0.plaidItemId == plaidItemId }
        setLinkedItems(current.isEmpty ? nil : current)
    }

    // MARK: - Auto-Refresh on Launch

    func refreshIfStale() async {
        guard let userId = currentUserId else {
            Logger.debug("BankDataManager: refreshIfStale - waiting for auth")
            return
        }

        // If refresh already in-flight, await it instead of starting another
        if let task = refreshTask {
            Logger.debug("BankDataManager: Refresh already in progress, awaiting existing task")
            await task.value
            return
        }

        let lastRefresh = persistence.getLastRefreshAt(for: userId)
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < refreshThreshold {
            Logger.debug("BankDataManager: Skipping refresh - last refresh was recent")
            return
        }

        refreshTask = Task {
            defer { refreshTask = nil }
            await refreshAllAccounts(for: userId)
        }

        await refreshTask?.value
    }

    private func refreshAllAccounts(for userId: String) async {
        guard currentUserId == userId else {
            Logger.debug("BankDataManager: User changed during refresh - aborting")
            return
        }

        guard let items = linkedItems, !items.isEmpty else { return }
        Logger.info("BankDataManager: Refreshing accounts for \(items.count) linked items")

        await withTaskGroup(of: Void.self) { group in
            var runningTasks = 0
            let maxConcurrency = 2

            for item in items {
                guard currentUserId == userId else { break }

                if runningTasks >= maxConcurrency {
                    await group.next()
                    runningTasks -= 1
                }

                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let response = try await self.fetchAccountsForItem(itemId: item.plaidItemId)
                        await MainActor.run {
                            // Final check: don't write if user changed during fetch
                            guard self.currentUserId == userId else { return }
                            self.accountsByItemId[item.plaidItemId] = response.accounts
                        }

                        // Persist accounts for instant display on next launch
                        if let persistence = self.accountPersistence {
                            await persistence.saveAccounts(response.accounts, for: userId, plaidItemId: item.plaidItemId)
                            await persistence.markRefreshComplete(for: userId, plaidItemId: item.plaidItemId)
                        }
                    } catch {
                        Logger.error("BankDataManager: Failed to refresh accounts for item")
                    }
                }
                runningTasks += 1
            }
        }

        persistence.setLastRefreshAt(Date(), for: userId)
    }

    // MARK: - Sign Out / Clear Data

    func clearAllData() {
        guard let userId = currentUserId else { return }
        linkedItems = nil
        accountsByItemId = [:]
        transactionsByItemId = [:]
        accounts = nil
        transactions = nil
        accountsSummary = nil
        accountsLastFetched = nil
        transactionsLastFetched = nil
        transactionsCacheKey = nil
        lastTransactionSyncAt = nil
        accountsError = nil
        transactionsError = nil
        syncError = nil
        persistence.clear(for: userId)

        // Cancel any in-flight refresh tasks
        for task in accountRefreshTasks.values {
            task.cancel()
        }
        accountRefreshTasks = [:]
        refreshTask?.cancel()
        refreshTask = nil
        linkedItemsFetchTask?.cancel()
        linkedItemsFetchTask = nil

        // Clear persisted data
        Task {
            if let txnPersistence = transactionPersistence {
                await txnPersistence.clearTransactions(for: userId)
            }
            if let acctPersistence = accountPersistence {
                await acctPersistence.clearAccounts(for: userId)
            }
        }

        currentUserId = nil
        Logger.info("BankDataManager: Cleared all bank data")
    }

    // MARK: - Disconnect Bank

    /// Disconnects a bank and clears all associated local data.
    /// - Important: Only clears local data AFTER server confirms disconnect.
    /// - Parameter plaidItemId: The Plaid item ID to disconnect
    func disconnectBank(plaidItemId: String) async throws {
        guard let userId = currentUserId else {
            throw BankError.unauthorized
        }

        // 1. Call API to revoke Plaid access (server-side)
        try await bankService.disconnectBankAccount(plaidItemId: plaidItemId)

        // 2. Only on success: clear all local data for this item

        // Cancel any in-flight refresh tasks for this item
        let taskKey = "\(userId)_\(plaidItemId)"
        accountRefreshTasks[taskKey]?.cancel()
        accountRefreshTasks.removeValue(forKey: taskKey)

        // Remove from in-memory linked items
        removeLinkedItem(plaidItemId: plaidItemId)

        // Remove accounts from in-memory cache
        accountsByItemId.removeValue(forKey: plaidItemId)

        // Remove transactions from in-memory cache
        transactionsByItemId.removeValue(forKey: plaidItemId)

        // 3. Clear persisted data
        await accountPersistence?.clearAccounts(for: userId, plaidItemId: plaidItemId)
        await transactionPersistence?.clearTransactions(for: userId, plaidItemId: plaidItemId)

        Logger.info("BankDataManager: Disconnected bank and cleared data for item \(plaidItemId)")
    }

    // MARK: - Bank Linking Flow

    /// Exchanges collected public tokens for access tokens via backend
    /// - Parameter publicTokens: Array of public tokens from Plaid Link (can be empty for sandbox "continue as guest")
    /// - Parameter useSandbox: If true, uses sandbox endpoint (for testing/guest mode)
    func completeLinking(with publicTokens: [String], useSandbox: Bool = false) async throws -> BankMultiConnectResponse {
        let sanitizedTokens = useSandbox ? publicTokens.filter { !$0.isEmpty } : publicTokens

        Logger.info("Connecting bank accounts (tokens: \(sanitizedTokens.count), sandbox: \(useSandbox))")

        let response = try await connectMultipleBankAccounts(
            publicTokens: sanitizedTokens.isEmpty && useSandbox ? [""] : sanitizedTokens,
            useSandbox: useSandbox
        )

        Logger.debug("Connection response: success=\(response.success), items=\(response.allConnectedItems?.count ?? 0)")

        guard response.success else {
            let message = response.message ?? "Unable to connect bank accounts."
            Logger.error("Connection failed: \(message)")
            throw BankError.multiConnectFailed(message)
        }

        try validateLinkingResponse(response, useSandbox: useSandbox)

        guard let connectedItems = response.allConnectedItems, !connectedItems.isEmpty else {
            Logger.warning("No connected items to sync")
            return response
        }

        setLinkedItems(connectedItems)
        Logger.success("Stored \(connectedItems.count) linked items")

        await syncConnectedItems(connectedItems)

        return response
    }

    private func validateLinkingResponse(_ response: BankMultiConnectResponse, useSandbox: Bool) throws {
        if useSandbox {
            if let itemsCreated = response.totalItemsCreated, itemsCreated == 0 {
                let message = response.message ?? "No items were created. Please try again."
                throw BankError.multiConnectFailed(message)
            }
        } else {
            if let failedItems = response.failedItems, !failedItems.isEmpty {
                let message = response.message ?? "Failed to connect \(failedItems.count) item(s). Please try again."
                throw BankError.multiConnectFailed(message)
            }

            if let connectedItems = response.allConnectedItems, connectedItems.isEmpty {
                let message = response.message ?? "No items were connected. Please try again."
                throw BankError.multiConnectFailed(message)
            }
        }
    }

    private func syncConnectedItems(_ connectedItems: [ConnectedItem]) async {
        let itemIds = connectedItems.map { $0.plaidItemId }
        Logger.info("Syncing \(itemIds.count) items...")

        do {
            let syncResponse = try await bankService.syncMultipleItems(itemIds: itemIds)
            Logger.success("Sync initiated: accounts=\(syncResponse.accountsUpdated ?? -1), transactions=\(syncResponse.transactionsUpdated ?? -1)")

            if syncResponse.accountsUpdated == nil {
                Logger.debug("Sync appears async, waiting 2 seconds...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            Logger.info("Fetching accounts after sync...")
            try await fetchAccounts(forceRefresh: true)
        } catch let error as BankError {
            Logger.warning("Sync failed with BankError: \(error)")
            if case .validationError(let details) = error {
                for detail in details {
                    Logger.debug("Validation: \(detail.loc.joined(separator: ".")) - \(detail.msg)")
                }
            }
            Logger.info("Attempting to fetch accounts despite sync failure...")
            try? await fetchAccounts(forceRefresh: true)
        } catch {
            Logger.warning("Sync failed: \(error.localizedDescription)")
            Logger.info("Attempting to fetch accounts despite sync failure...")
            try? await fetchAccounts(forceRefresh: true)
        }
    }

    // MARK: - Account Management

    /// Fetches bank accounts from the API
    /// - Parameter forceRefresh: If true, bypasses cache and fetches fresh data
    func fetchAccounts(forceRefresh: Bool = false) async throws {
        if !forceRefresh,
           accounts != nil,
           let lastFetched = accountsLastFetched,
           Date().timeIntervalSince(lastFetched) < cacheTTL {
            return
        }

        isLoadingAccounts = true
        accountsError = nil
        defer { isLoadingAccounts = false }

        do {
            Logger.info("Fetching accounts from API...")
            let fetchedAccounts = try await bankService.getBankAccounts()

            Logger.success("Fetched \(fetchedAccounts.count) accounts")

            accounts = fetchedAccounts
            accountsLastFetched = Date()
        } catch let error as BankError {
            Logger.error("BankError fetching accounts: \(error)")
            accountsError = error
            throw error
        } catch {
            Logger.error("Unknown error fetching accounts: \(error)")
            let bankError = BankError.networkError
            accountsError = bankError
            throw bankError
        }
    }

    /// Fetches the full accounts response including summary data
    func fetchAccountsSummary(forceRefresh: Bool = false) async throws {
        try await fetchAccounts(forceRefresh: forceRefresh)
    }

    /// Fetches bank accounts for a specific item
    /// - Parameters:
    ///   - itemId: The item ID to fetch accounts for
    /// - Returns: ItemAccountsResponse containing accounts for that item
    func fetchAccountsForItem(itemId: String) async throws -> ItemAccountsResponse {
        Logger.info("Fetching accounts for item \(itemId)")

        do {
            let response = try await bankService.getAccountsByItemId(itemId: itemId)
            Logger.success("Fetched \(response.accounts.count) accounts for item \(itemId)")
            return response
        } catch let error as BankError {
            Logger.error("BankError fetching accounts for item \(itemId): \(error)")
            throw error
        } catch {
            Logger.error("Unknown error fetching accounts for item \(itemId): \(error)")
            throw BankError.networkError
        }
    }

    /// Connects multiple bank accounts using public tokens returned from Plaid Link
    /// - Parameter publicTokens: Array of public tokens collected from Plaid Link sessions
    /// - Parameter useSandbox: If true, uses the sandbox endpoint for testing
    func connectMultipleBankAccounts(publicTokens: [String], useSandbox: Bool = false) async throws -> BankMultiConnectResponse {
        guard !publicTokens.isEmpty else {
            throw BankError.validationError([ValidationErrorDetail(loc: ["public_tokens"], msg: "No public tokens provided", type: "value_error")])
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let response: BankMultiConnectResponse
            if useSandbox {
                response = try await bankService.createSandboxMultiItems(publicTokens: publicTokens)
            } else {
                response = try await bankService.connectMultipleBankAccounts(publicTokens: publicTokens)
            }
            return response
        } catch let error as BankError {
            syncError = error
            throw error
        } catch {
            syncError = .networkError
            throw BankError.networkError
        }
    }

    // MARK: - Transaction Management

    /// Fetches transactions from the API
    /// - Parameters:
    ///   - accountId: Optional account ID to filter transactions
    ///   - limit: Optional limit for pagination
    ///   - offset: Optional offset for pagination
    ///   - forceRefresh: If true, bypasses cache and fetches fresh data
    func fetchTransactions(
        accountId: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        forceRefresh: Bool = false
    ) async throws {
        let cacheKey = "\(accountId ?? "all")-\(limit ?? 0)-\(offset ?? 0)"

        if !forceRefresh,
           cacheKey == transactionsCacheKey,
           transactions != nil,
           let lastFetched = transactionsLastFetched,
           Date().timeIntervalSince(lastFetched) < cacheTTL {
            return
        }

        isLoadingTransactions = true
        transactionsError = nil
        defer { isLoadingTransactions = false }

        do {
            let fetchedTransactions = try await bankService.getTransactions(
                accountId: accountId,
                limit: limit,
                offset: offset
            )

            transactions = fetchedTransactions
            transactionsLastFetched = Date()
            transactionsCacheKey = cacheKey
        } catch let error as BankError {
            transactionsError = error
            throw error
        } catch {
            let bankError = BankError.networkError
            transactionsError = bankError
            throw bankError
        }
    }

    /// Fetches recent transactions for a specific account with instant cache display
    /// - Parameters:
    ///   - accountId: The account ID to fetch transactions for
    ///   - plaidItemId: The Plaid item ID the account belongs to
    ///   - limit: Maximum number of transactions to return (default 50)
    /// - Returns: Array of transactions for that account, from cache or network
    func fetchRecentTransactions(
        accountId: String,
        plaidItemId: String,
        limit: Int = 50
    ) async throws -> [Transaction] {
        guard let userId = currentUserId else {
            throw BankError.unauthorized
        }

        // 1. Try to return cached data immediately
        if let persistence = transactionPersistence {
            let cached = await persistence.loadTransactions(
                for: userId,
                plaidAccountId: accountId,
                limit: limit,
                before: nil
            )

            if !cached.isEmpty {
                // Trigger background refresh if stale
                if await persistence.needsRecentSync(for: userId, plaidItemId: plaidItemId) {
                    Task { await backgroundRefreshTransactions(plaidItemId: plaidItemId) }
                }
                return cached
            }
        }

        // 2. Check in-memory cache
        if let cached = transactionsByItemId[plaidItemId] {
            let filtered = cached.filter { $0.accountId == accountId }
            if !filtered.isEmpty {
                return Array(filtered.prefix(limit))
            }
        }

        // 3. No cache: fetch from network (blocking)
        return try await fetchAndPersistTransactions(plaidItemId: plaidItemId, accountId: accountId, limit: limit)
    }

    /// Loads more transactions from local cache for infinite scroll
    /// - Parameters:
    ///   - accountId: The account ID to load transactions for
    ///   - before: Load transactions before this date
    ///   - limit: Maximum number of transactions to return (default 50)
    /// - Returns: Array of older transactions from cache
    func fetchMoreTransactions(
        accountId: String,
        before: Date,
        limit: Int = 50
    ) async -> [Transaction] {
        guard let userId = currentUserId, let persistence = transactionPersistence else {
            return []
        }

        return await persistence.loadTransactions(
            for: userId,
            plaidAccountId: accountId,
            limit: limit,
            before: before
        )
    }

    /// Fetches transactions for a specific Plaid item
    /// - Parameters:
    ///   - plaidItemId: The Plaid item ID to fetch transactions for
    ///   - forceRefresh: If true, bypasses cache and fetches fresh data
    /// - Returns: Array of transactions for that item
    func fetchTransactionsForItem(plaidItemId: String, forceRefresh: Bool = false) async throws -> [Transaction] {
        guard let userId = currentUserId else {
            throw BankError.unauthorized
        }

        // 1. Check in-memory cache first
        if !forceRefresh, let cached = transactionsByItemId[plaidItemId] {
            // Trigger background refresh if stale
            if let persistence = transactionPersistence,
               await persistence.needsRecentSync(for: userId, plaidItemId: plaidItemId) {
                Task { await backgroundRefreshTransactions(plaidItemId: plaidItemId) }
            }
            return cached
        }

        // 2. Check persisted cache
        if !forceRefresh, let persistence = transactionPersistence {
            let persisted = await persistence.loadAllTransactions(for: userId, plaidItemId: plaidItemId)
            if !persisted.isEmpty {
                transactionsByItemId[plaidItemId] = persisted
                // Trigger background refresh if stale
                if await persistence.needsRecentSync(for: userId, plaidItemId: plaidItemId) {
                    Task { await backgroundRefreshTransactions(plaidItemId: plaidItemId) }
                }
                return persisted
            }
        }

        // 3. No cache: fetch from network (blocking)
        isLoadingTransactions = true
        transactionsError = nil
        defer { isLoadingTransactions = false }

        do {
            let fetchedTransactions = try await bankService.getTransactionsForItem(plaidItemId: plaidItemId)
            transactionsByItemId[plaidItemId] = fetchedTransactions

            // Persist for future instant display
            if let persistence = transactionPersistence {
                await persistence.saveTransactions(fetchedTransactions, for: userId, plaidItemId: plaidItemId)
                await persistence.markFullSyncComplete(for: userId, plaidItemId: plaidItemId)
            }

            lastTransactionSyncAt = Date()
            return fetchedTransactions
        } catch let error as BankError {
            transactionsError = error
            throw error
        } catch {
            let bankError = BankError.networkError
            transactionsError = bankError
            throw bankError
        }
    }

    // MARK: - Background Refresh

    /// Refreshes transactions in background without blocking UI
    private func backgroundRefreshTransactions(plaidItemId: String) async {
        guard let userId = currentUserId else { return }

        isSyncing = true
        defer {
            isSyncing = false
            lastTransactionSyncAt = Date()
        }

        do {
            let fetchedTransactions = try await bankService.getTransactionsForItem(plaidItemId: plaidItemId)
            transactionsByItemId[plaidItemId] = fetchedTransactions

            if let persistence = transactionPersistence {
                await persistence.saveTransactions(fetchedTransactions, for: userId, plaidItemId: plaidItemId)
                await persistence.markRecentSyncComplete(for: userId, plaidItemId: plaidItemId)
            }

            Logger.debug("BankDataManager: Background refresh completed for item \(plaidItemId)")
        } catch {
            Logger.warning("BankDataManager: Background refresh failed: \(error.localizedDescription)")
        }
    }

    /// Fetches transactions from network and persists them
    private func fetchAndPersistTransactions(
        plaidItemId: String,
        accountId: String,
        limit: Int
    ) async throws -> [Transaction] {
        guard let userId = currentUserId else {
            throw BankError.unauthorized
        }

        isLoadingTransactions = true
        transactionsError = nil
        defer { isLoadingTransactions = false }

        do {
            let fetchedTransactions = try await bankService.getTransactionsForItem(plaidItemId: plaidItemId)
            transactionsByItemId[plaidItemId] = fetchedTransactions

            // Persist for future instant display
            if let persistence = transactionPersistence {
                await persistence.saveTransactions(fetchedTransactions, for: userId, plaidItemId: plaidItemId)
                await persistence.markFullSyncComplete(for: userId, plaidItemId: plaidItemId)
            }

            lastTransactionSyncAt = Date()

            // Filter and return for the requested account
            let filtered = fetchedTransactions.filter { $0.accountId == accountId }
            return Array(filtered.prefix(limit))
        } catch let error as BankError {
            transactionsError = error
            throw error
        } catch {
            let bankError = BankError.networkError
            transactionsError = bankError
            throw bankError
        }
    }

    // MARK: - Sync Management

    /// Syncs bank data for a specific Plaid item
    /// - Parameter plaidItemId: The Plaid item ID to sync
    func syncBankData(plaidItemId: String) async throws {
        isSyncing = true
        syncError = nil

        do {
            _ = try await bankService.syncBankData(plaidItemId: plaidItemId)

            isSyncing = false

            try await fetchAccounts(forceRefresh: true)

            if transactionsCacheKey != nil {
                clearTransactionsCache()
            }
        } catch let error as BankError {
            syncError = error
            isSyncing = false
            throw error
        } catch {
            let bankError = BankError.networkError
            syncError = bankError
            isSyncing = false
            throw bankError
        }
    }

    // MARK: - Cache Management

    /// Clears all cached data
    func clearCache() {
        accounts = nil
        transactions = nil
        accountsSummary = nil
        accountsLastFetched = nil
        transactionsLastFetched = nil
        transactionsCacheKey = nil
    }

    /// Clears only transaction cache
    func clearTransactionsCache() {
        transactions = nil
        transactionsLastFetched = nil
        transactionsCacheKey = nil
    }

    /// Clears only accounts cache
    func clearAccountsCache() {
        accounts = nil
        accountsSummary = nil
        accountsLastFetched = nil
    }

    // MARK: - Helper Methods

    /// Gets account by ID
    func getAccount(by id: String) -> BankAccount? {
        accounts?.first { $0.idAccount == id }
    }

    /// Gets transactions for a specific account
    func getTransactions(for accountId: String) -> [Transaction] {
        transactions?.filter { $0.accountId == accountId } ?? []
    }

    /// Checks if accounts data is stale (older than cache TTL)
    var isAccountsDataStale: Bool {
        guard let lastFetched = accountsLastFetched else { return true }
        return Date().timeIntervalSince(lastFetched) >= cacheTTL
    }

    /// Checks if transactions data is stale (older than cache TTL)
    var isTransactionsDataStale: Bool {
        guard let lastFetched = transactionsLastFetched else { return true }
        return Date().timeIntervalSince(lastFetched) >= cacheTTL
    }

    // MARK: - Account Grouping Helpers

    /// Groups all accounts by institution (plaid item ID)
    func accountsGroupedByInstitution() -> [String: [BankAccount]] {
        guard let linkedItems = linkedItems else { return [:] }

        var grouped: [String: [BankAccount]] = [:]
        for item in linkedItems {
            grouped[item.plaidItemId] = accountsByItemId[item.plaidItemId] ?? []
        }
        return grouped
    }

    /// Groups all accounts by account type
    func accountsGroupedByType() -> [String: [BankAccount]] {
        var grouped: [String: [BankAccount]] = [:]
        let allAccounts = accountsByItemId.values.flatMap { $0 }

        for account in allAccounts {
            let type = account.type.lowercased()
            if grouped[type] == nil {
                grouped[type] = []
            }
            grouped[type]?.append(account)
        }

        return grouped
    }

    /// Calculates total balance across all accounts
    func totalBalance() -> Double {
        accountsByItemId.values.flatMap { $0 }.reduce(0) { $0 + $1.currentBalance }
    }

    /// Gets total account count
    func totalAccountCount() -> Int {
        accountsByItemId.values.flatMap { $0 }.count
    }

    /// Gets account count for a specific type
    func accountCount(forType type: String) -> Int {
        accountsByItemId.values.flatMap { $0 }.filter { $0.type.lowercased() == type.lowercased() }.count
    }

    /// Gets all accounts for a specific institution
    func accountsForInstitution(itemId: String) -> [BankAccount] {
        accountsByItemId[itemId] ?? []
    }

    /// Gets total balance for a specific institution
    func totalBalanceForInstitution(itemId: String) -> Double {
        accountsForInstitution(itemId: itemId).reduce(0) { $0 + $1.currentBalance }
    }
}
