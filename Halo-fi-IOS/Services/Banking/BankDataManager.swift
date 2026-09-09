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
    private(set) var balanceSummary: VerifiedBalanceSummary?

    /// Linked items (institutions) from Plaid - use mutation methods to modify
    private(set) var linkedItems: [ConnectedItem]?

    /// Accounts grouped by item ID - fetched on demand using GET /bank/{item_id}/account
    var accountsByItemId: [String: [BankAccount]] = [:]

    /// Transactions grouped by item ID - fetched on demand
    var transactionsByItemId: [String: [Transaction]] = [:]

    /// User-entered accounts (not from Plaid). Sourced from
    /// /bank/manual-accounts and refreshed via refreshManualAccounts().
    /// Surfaces alongside the Plaid lists in AccountsView.
    private(set) var manualAccounts: [ManualAccount] = []

    var isLoadingAccounts = false
    var isLoadingTransactions = false
    var isSyncing = false

    /// False until the first configuration pass has finished. With nothing
    /// cached, the Money hero shows "Loading your accounts" instead of $0.
    private(set) var hasCompletedInitialLoad = false
    var isInitialLoad: Bool {
        !hasCompletedInitialLoad && (accounts ?? []).isEmpty && accountsByItemId.isEmpty && manualAccounts.isEmpty
    }

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

    /// In-flight account refresh tasks keyed by (userId, itemId) to prevent refresh storms
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
        // A different person than last time: nothing of theirs may linger.
        if let previous = currentUserId, previous != userId {
            clearAllData()
        }
        currentUserId = userId
        SnapshotCache.currentUserId = userId
        // Fixture launches have no authenticated account. Do not restore
        // disk data or start a bank request that can expire the test session
        // and clear the profile just seeded by MainTabView.
        guard !UITestArchetype.isActive else { return }
        Diagnostics.send("sign_in", ["restored_manual": "\(manualAccounts.count)"])
        // Last known manual accounts draw immediately; the refresh below replaces them.
        if manualAccounts.isEmpty, let cached = SnapshotCache.load([ManualAccount].self, key: "manual_accounts", userId: userId) {
            manualAccounts = cached
        }

        if balanceSummary == nil, let cached = SnapshotCache.load(VerifiedBalanceSummary.self, key: "verified_balances", userId: userId), cached.isValid {
            balanceSummary = cached
        }
        let generation = SessionLifetime.shared.current
        Task { @MainActor in
            guard SessionLifetime.shared.isCurrent(generation), currentUserId == userId else { return }
            // 1. Restore linked items - return value for explicit ordering
            let restoredItems = restoreLinkedItemsSync()

            // 2. If persistence was empty, fetch from server (includes embedded accounts)
            if restoredItems.isEmpty {
                await fetchLinkedItemsFromServer()
                guard SessionLifetime.shared.isCurrent(generation), currentUserId == userId else { return }
                // fetchLinkedItemsFromServer populates accountsByItemId with embedded accounts
                // and sets lastRefreshAt, so we can skip the rest
                notifyConfigurationComplete()
                return
            }

            // 3. Restore accounts from persistence for the first paint only.
            await restoreAccounts()
            guard SessionLifetime.shared.isCurrent(generation), currentUserId == userId else { return }

            // 4. Always confirm with the server (2026-09-05). /bank/multi-items
            //    is a database read (no Plaid call), and the disk copy can be
            //    hours old: Liam's Chase kept showing three accounts for five
            //    minutes after every launch because the "recent refresh"
            //    guard skipped this.
            if !UITestArchetype.isActive { await fetchLinkedItemsFromServer() }
            guard SessionLifetime.shared.isCurrent(generation), currentUserId == userId else { return }

            // 5. Anything else that is stale (guarded)
            await refreshIfStale()
            guard SessionLifetime.shared.isCurrent(generation), currentUserId == userId else { return }

            // 5. Ensure accountsByItemId is populated from accounts property
            rebuildAccountsByItemId()

            // 6. Notify UserManager that configuration is complete
            notifyConfigurationComplete()
        }
    }

    /// Posts notification that bank data configuration is complete
    /// Used by UserManager to determine onboarding destination
    private func notifyConfigurationComplete() {
        hasCompletedInitialLoad = true
        let hasAccounts = !accountsByItemId.isEmpty || (accounts?.isEmpty == false)
        Logger.info("BankDataManager: Configuration complete, hasAccounts=\(hasAccounts)")
        NotificationCenter.default.post(
            name: .bankDataConfigurationComplete,
            object: nil,
            userInfo: ["hasAccounts": hasAccounts]
        )
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
        let generation = SessionLifetime.shared.current
        let requestedUserId = currentUserId
        // If task already in-flight, await it instead of returning early
        if let task = linkedItemsFetchTask {
            await task.value
            return
        }

        linkedItemsFetchTask = Task {
            defer { if SessionLifetime.shared.isCurrent(generation), currentUserId == requestedUserId { linkedItemsFetchTask = nil } }

            do {
                let response = try await bankService.getLinkedItems()
                guard SessionLifetime.shared.isCurrent(generation), currentUserId == requestedUserId, !Task.isCancelled else { return }

                // Map server items to ConnectedItem and apply userId
                var items = response.items.map { ConnectedItem(from: $0) }
                if let userId = requestedUserId {
                    items = items.map { $0.withUserId(userId) }
                }


                // Extract embedded accounts from each item (keyed by internal itemId)
                var embeddedAccountsByItemId: [String: [BankAccount]] = [:]
                for serverItem in response.items {
                    if let serverAccounts = serverItem.accounts, !serverAccounts.isEmpty {
                        let bankAccounts = serverAccounts.map { $0.toBankAccount(plaidItemId: serverItem.plaidItemId) }
                        embeddedAccountsByItemId[serverItem.itemId] = bankAccounts
                    }
                }

                await MainActor.run {
                    guard SessionLifetime.shared.isCurrent(generation), currentUserId == requestedUserId else { return }
                    if let summary = response.balanceSummary, summary.isValid {
                        balanceSummary = summary
                        if let userId = requestedUserId {
                            SnapshotCache.save(summary, key: "verified_balances", userId: userId)
                        }
                    } else {
                        balanceSummary = nil
                    }
                    setLinkedItems(items)  // Sets property + persists
                    // Drop in-memory accounts for connections the server no longer lists.
                    let serverIds = Set(items.map(\.itemId))
                    accountsByItemId = accountsByItemId.filter { serverIds.contains($0.key) }
                    if items.isEmpty {
                        accounts = []
                        transactions = []
                        accountsSummary = nil
                        transactionsByItemId = [:]
                    }

                    // Populate accountsByItemId with embedded accounts (REPLACE, not merge)
                    if !embeddedAccountsByItemId.isEmpty {
                        // Clear existing and replace with fresh data
                        accountsByItemId = embeddedAccountsByItemId

                        // Also set the flat accounts array (used by PlaidOnboardingViewModel.bootstrapIfNeeded)
                        // This prevents a redundant /bank/accounts fetch
                        let allAccounts = embeddedAccountsByItemId.values.flatMap { $0 }
                        self.accounts = allAccounts
                        self.accountsLastFetched = Date()

                        Logger.success("BankDataManager: Populated \(embeddedAccountsByItemId.count) items with \(allAccounts.count) embedded accounts")

                        // Mark as refreshed to prevent redundant refreshIfStale
                        if let userId = requestedUserId {
                            persistence.setLastRefreshAt(Date(), for: userId)
                        }
                    }
                    logAccountMap("server items")
                }
                // Keep the disk copy in step with the server: refreshAllAccounts
                // used to be the only writer, so a bank that changed between
                // pull-to-refreshes was restored stale on the next launch.
                if let userId = requestedUserId, let persistence = accountPersistence {
                    for (itemId, list) in embeddedAccountsByItemId {
                        guard SessionLifetime.shared.isCurrent(generation), currentUserId == userId else { return }
                        await persistence.saveAccounts(list, for: userId, itemId: itemId)
                    }
                }
                // Persisted accounts of retired connections would otherwise be
                // restored on the next launch (2026-09-05).
                if let userId = requestedUserId, let persistence = accountPersistence {
                    let serverIds = Set(items.map(\.itemId))
                    let onDisk = await persistence.loadAllAccounts(for: userId)
                    guard SessionLifetime.shared.isCurrent(generation), currentUserId == userId else { return }
                    for staleId in onDisk.keys where !serverIds.contains(staleId) {
                        await persistence.clearAccounts(for: userId, itemId: staleId)
                    }
                }
                Logger.success("BankDataManager: Fetched \(items.count) linked items from server")
            } catch {
                guard SessionLifetime.shared.isCurrent(generation), currentUserId == requestedUserId else { return }
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
    /// Keys by internal itemId, looking up from linkedItems
    /// One line per write to the account map: item count, account count,
    /// cash total. The Money hero flipping between two totals (Liam,
    /// 2026-09-05) was invisible without it.
    private func logAccountMap(_ source: String) {
        let all = accountsByItemId.values.flatMap { $0 }
        let cash = all.filter { $0.isActive && !["credit", "loan"].contains($0.type.lowercased()) }
            .reduce(0.0) { $0 + max(0, $1.currentBalance ?? 0) }
        Logger.info("BankDataManager: account map (\(source)): \(accountsByItemId.count) items, \(all.count) accounts, cash \(Int(cash))")
        Diagnostics.send("account_map", ["source": source, "items": "\(accountsByItemId.count)", "accounts": "\(all.count)",
                                         "cash": "\(Int(cash))", "manual": "\(manualAccounts.count)", "linked": "\((linkedItems ?? []).count)"])
    }

    private func rebuildAccountsByItemId() {
        guard let accounts = accounts, !accounts.isEmpty else { return }

        // Build lookup from plaidItemId -> itemId using linkedItems
        var plaidToItemId: [String: String] = [:]
        if let items = linkedItems {
            for item in items {
                plaidToItemId[item.plaidItemId] = item.itemId
            }
        }

        var newCache: [String: [BankAccount]] = [:]
        for account in accounts {
            guard let plaidItemId = account.plaidItemId else { continue }
            // Use itemId from linkedItems, fallback to plaidItemId if not found
            let key = plaidToItemId[plaidItemId] ?? plaidItemId
            newCache[key, default: []].append(account)
        }
        // MERGE (2026-09-05): the flat list can lag the per-item map (a bank
        // linked minutes ago, an account without an item id). Replacing the
        // whole map made the Money hero flip between two totals as the
        // paths took turns. Items the flat list did not cover keep what
        // they had.
        for (key, list) in newCache { accountsByItemId[key] = list }
        logAccountMap("rebuilt from flat list")
    }

    private func restoreAccounts() async {
        let generation = SessionLifetime.shared.current
        guard let userId = currentUserId, let persistence = accountPersistence else { return }

        var accountsByItem = await persistence.loadAllAccounts(for: userId)
        guard SessionLifetime.shared.isCurrent(generation), currentUserId == userId else { return }
        // Only items that are still linked: a retired connection's accounts
        // must never come back from disk (2026-09-05).
        if let linked = linkedItems {
            let ids = Set(linked.map(\.itemId))
            accountsByItem = accountsByItem.filter { ids.contains($0.key) }
        }
        if !accountsByItem.isEmpty && accountsByItemId.isEmpty {
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
        if !current.contains(where: { $0.itemId == item.itemId }) {
            current.append(item)
        }
        setLinkedItems(current)
    }

    func removeLinkedItem(itemId: String) {
        guard var current = linkedItems else { return }
        current.removeAll { $0.itemId == itemId }
        setLinkedItems(current.isEmpty ? nil : current)
    }

    // MARK: - Force Refresh

    func forceRefresh() async {
        if UITestArchetype.isActive { return }
        guard let userId = currentUserId else {
            Logger.debug("BankDataManager: forceRefresh - no user")
            return
        }

        if let task = refreshTask {
            await task.value
            return
        }

        refreshTask = Task {
            defer { refreshTask = nil }
            // Fetch linked items first so refreshAllAccounts has items to iterate
            await fetchLinkedItemsFromServer()
            await refreshAllAccounts(for: userId)
            await refreshManualAccounts()
        }

        await refreshTask?.value
    }

    // MARK: - Auto-Refresh on Launch

    func refreshIfStale() async {
        if UITestArchetype.isActive { return }
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

        // If linked items fetch is in progress, wait for it - it will populate accounts
        if let task = linkedItemsFetchTask {
            Logger.debug("BankDataManager: Linked items fetch in progress, awaiting it")
            await task.value
            return
        }

        // Two reasons we'd skip a refresh: (1) the last refresh was recent
        // enough that data is still warm, or (2) we hit a startup race where
        // configureForUser already populated accounts. The previous version
        // collapsed both into "accounts populated → skip", which suppressed
        // legitimate stale-data refreshes for the entire app session.
        let lastRefresh = persistence.getLastRefreshAt(for: userId)
        let isRecent = lastRefresh.map { Date().timeIntervalSince($0) < refreshThreshold } ?? false

        if isRecent {
            Logger.debug("BankDataManager: Skipping refresh - last refresh was recent")
            return
        }

        // If accounts are populated AND we have a recent-ish lastRefresh,
        // we can still skip (covers the configureForUser race). But with
        // no lastRefresh recorded, we MUST refresh — otherwise restored
        // accounts from local persistence stay forever stale.
        if lastRefresh != nil, let items = linkedItems, !items.isEmpty {
            let hasAllAccounts = items.allSatisfy { item in
                guard let accounts = accountsByItemId[item.itemId] else { return false }
                return !accounts.isEmpty
            }
            if hasAllAccounts && Date().timeIntervalSince(lastRefresh!) < refreshThreshold * 2 {
                Logger.debug("BankDataManager: Skipping refresh - accounts populated and refresh within 2x threshold")
                return
            }
        }

        refreshTask = Task {
            defer { refreshTask = nil }
            await refreshAllAccounts(for: userId)
            await refreshManualAccounts()
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
                        let response = try await self.fetchAccountsForItem(itemId: item.itemId)
                        await MainActor.run {
                            // Final check: don't write if user changed during fetch
                            guard self.currentUserId == userId else { return }
                            self.accountsByItemId[item.itemId] = response.accounts
                            self.logAccountMap("per-item \(item.institutionName)")
                        }

                        // Persist accounts for instant display on next launch
                        if let persistence = self.accountPersistence {
                            await persistence.saveAccounts(response.accounts, for: userId, itemId: item.itemId)
                            await persistence.markRefreshComplete(for: userId, itemId: item.itemId)
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
        SessionLifetime.shared.invalidate { }
        let userId = currentUserId
        Diagnostics.send("sign_out", ["manual_accounts": "\(manualAccounts.count)", "items": "\(accountsByItemId.count)"])
        if let userId { SnapshotCache.clear(userId: userId) }
        hasCompletedInitialLoad = false
        // Manual accounts were never cleared here (2026-09-06): the review
        // account's three mock accounts followed Liam into his own account.
        manualAccounts = []
        linkedItems = nil
        accountsByItemId = [:]
        transactionsByItemId = [:]
        accounts = nil
        transactions = nil
        accountsSummary = nil
        balanceSummary = nil
        accountsLastFetched = nil
        transactionsLastFetched = nil
        transactionsCacheKey = nil
        lastTransactionSyncAt = nil
        accountsError = nil
        transactionsError = nil
        syncError = nil
        if let userId { persistence.clear(for: userId) }
        NotificationCenter.default.post(name: .userDataCleared, object: nil)

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
            guard let userId else { return }
            if let txnPersistence = transactionPersistence {
                await txnPersistence.clearTransactions(for: userId)
            }
            if let acctPersistence = accountPersistence {
                await acctPersistence.clearAccounts(for: userId)
            }
        }

        for task in inflightItemFetches.values { task.cancel() }
        inflightItemFetches = [:]
        inflightAllFetch?.cancel()
        inflightAllFetch = nil
        isLoadingAccounts = false
        isLoadingTransactions = false
        isSyncing = false
        currentUserId = nil
        Logger.info("BankDataManager: Cleared all bank data")
    }

    // MARK: - Disconnect Bank

    /// Disconnects a bank and clears all associated local data.
    /// - Important: Only clears local data AFTER server confirms disconnect.
    /// - Parameter itemId: The internal bank item UUID to disconnect
    func disconnectBank(itemId: String) async throws {
        guard let userId = currentUserId else {
            throw BankError.unauthorized
        }

        // 1. Call API to revoke access (server-side)
        try await bankService.disconnectBankAccount(itemId: itemId)

        // 2. Only on success: clear all local data for this item

        // Cancel any in-flight refresh tasks for this item
        let taskKey = "\(userId)_\(itemId)"
        accountRefreshTasks[taskKey]?.cancel()
        accountRefreshTasks.removeValue(forKey: taskKey)

        // Remove from in-memory linked items
        removeLinkedItem(itemId: itemId)

        // Remove accounts from in-memory cache
        accountsByItemId.removeValue(forKey: itemId)

        // Remove transactions from in-memory cache
        transactionsByItemId.removeValue(forKey: itemId)

        // 3. Clear persisted data
        await accountPersistence?.clearAccounts(for: userId, itemId: itemId)
        await transactionPersistence?.clearTransactions(for: userId, itemId: itemId)

        Logger.info("BankDataManager: Disconnected bank and cleared data for item \(itemId)")
    }

    // MARK: - Bank Linking Flow

    /// Exchanges collected public tokens for access tokens via backend
    /// - Parameter publicTokens: Array of public tokens from Plaid Link (can be empty for sandbox "continue as guest")
    /// - Parameter useSandbox: If true, uses sandbox endpoint (for testing/guest mode)
    func completeLinking(with publicTokens: [String], useSandbox: Bool = false) async throws -> BankMultiConnectResponse {
        let sanitizedTokens = useSandbox ? publicTokens.filter { !$0.isEmpty } : publicTokens

        Logger.info("BankDataManager: completeLinking started (tokens: \(sanitizedTokens.count), sandbox: \(useSandbox))")

        let response = try await connectMultipleBankAccounts(
            publicTokens: sanitizedTokens.isEmpty && useSandbox ? [""] : sanitizedTokens,
            useSandbox: useSandbox
        )

        guard response.success else {
            let message = response.message ?? "Unable to connect bank accounts."
            Logger.error("BankDataManager: Connection failed - \(message)")
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
        let itemIds = connectedItems.map { $0.itemId }
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
        let generation = SessionLifetime.shared.current
        if !forceRefresh,
           accounts != nil,
           let lastFetched = accountsLastFetched,
           Date().timeIntervalSince(lastFetched) < cacheTTL {
            return
        }

        isLoadingAccounts = true
        accountsError = nil
        defer { if SessionLifetime.shared.isCurrent(generation) { isLoadingAccounts = false } }

        do {
            Logger.info("Fetching accounts from API...")
            let fetchedAccounts = try await bankService.getBankAccounts()

            Logger.success("Fetched \(fetchedAccounts.count) accounts")

            try SessionLifetime.shared.check(generation)
            accounts = fetchedAccounts
            accountsLastFetched = Date()
        } catch let error as BankError {
            try SessionLifetime.shared.check(generation)
            Logger.error("BankError fetching accounts: \(error)")
            accountsError = error
            throw error
        } catch {
            try SessionLifetime.shared.check(generation)
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

    /// Reloads the user's manual (non-Plaid) accounts from the backend.
    /// Called by the form view after create/update/delete and from the
    /// regular refresh paths so the lists stay current. Failures log
    /// but don't surface — manual accounts are non-critical.
    func refreshManualAccounts() async {
        guard let userId = currentUserId else { return }
        let generation = SessionLifetime.shared.current
        do {
            let result = try await ManualAccountService.shared.list()
            guard currentUserId == userId, SessionLifetime.shared.isCurrent(generation), !Task.isCancelled else { return }
            manualAccounts = result
            SnapshotCache.save(result, key: "manual_accounts", userId: userId)
            Logger.success("BankDataManager: loaded \(manualAccounts.count) manual account(s)")
        } catch {
            Logger.warning("BankDataManager: refreshManualAccounts failed — \(error)")
        }
    }

    /// Fetches bank accounts for a specific item
    /// - Parameters:
    ///   - itemId: The item ID to fetch accounts for
    /// - Returns: ItemAccountsResponse containing accounts for that item
    /// A one-line notice from the last link ("fewer accounts than you
    /// picked"); the Accounts screen shows it once.
    var lastLinkNotice: String? = nil

    /// Sets a nickname and updates every cached copy of the account so rows
    /// and the balance card speak it at once.
    func setNickname(_ nickname: String, for account: BankAccount) async throws {
        let updated = try await bankService.setAccountNickname(accountId: account.idAccount, nickname: nickname)
        await MainActor.run {
            for (itemId, list) in accountsByItemId {
                accountsByItemId[itemId] = list.map { $0.idAccount == updated.idAccount ? updated : $0 }
            }
            if let all = accounts { accounts = all.map { $0.idAccount == updated.idAccount ? updated : $0 } }
        }
    }

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
        let generation = SessionLifetime.shared.current
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
        defer { if SessionLifetime.shared.isCurrent(generation) { isLoadingTransactions = false } }

        do {
            let fetchedTransactions = try await bankService.getTransactions(
                accountId: accountId,
                limit: limit,
                offset: offset
            )

            try SessionLifetime.shared.check(generation)
            transactions = fetchedTransactions
            transactionsLastFetched = Date()
            transactionsCacheKey = cacheKey
        } catch let error as BankError {
            try SessionLifetime.shared.check(generation)
            transactionsError = error
            throw error
        } catch {
            try SessionLifetime.shared.check(generation)
            let bankError = BankError.networkError
            transactionsError = bankError
            throw bankError
        }
    }

    /// Fetches recent transactions for a specific account with instant cache display
    /// - Parameters:
    ///   - accountId: The account ID to fetch transactions for
    ///   - itemId: The internal bank item UUID
    ///   - limit: Maximum number of transactions to return (default 50)
    /// - Returns: Array of transactions for that account, from cache or network
    func fetchRecentTransactions(
        accountId: String,
        itemId: String,
        limit: Int = 50
    ) async throws -> [Transaction] {
        let generation = SessionLifetime.shared.current
        guard let userId = currentUserId else {
            throw BankError.unauthorized
        }

        // 1. Try to return cached data immediately
        if let persistence = transactionPersistence {
            let cached = await persistence.loadTransactions(
                for: userId,
                accountId: accountId,
                limit: limit,
                before: nil
            )
            let needsFullSync = await persistence.needsFullSync(for: userId, itemId: itemId)

            // Return if we have transactions OR we've already synced (empty is a valid state)
            if !cached.isEmpty || !needsFullSync {
                // Trigger background refresh if stale
                if await persistence.needsRecentSync(for: userId, itemId: itemId) {
                    try SessionLifetime.shared.check(generation)
                    Task { await backgroundRefreshTransactions(itemId: itemId) }
                }
                try SessionLifetime.shared.check(generation)
                return cached
            }
        }

        // 2. Check in-memory cache - if we've fetched for this item, use the result
        // (even if this specific account has no transactions)
        if let cached = transactionsByItemId[itemId] {
            let filtered = cached.filter { $0.accountId == accountId }
            // Trigger background refresh if stale
            if let persistence = transactionPersistence,
               await persistence.needsRecentSync(for: userId, itemId: itemId) {
                try SessionLifetime.shared.check(generation)
                Task { await backgroundRefreshTransactions(itemId: itemId) }
            }
            try SessionLifetime.shared.check(generation)
            return Array(filtered.prefix(limit))
        }

        // 3. No cache: fetch from network (blocking)
        try SessionLifetime.shared.check(generation)
        return try await fetchAndPersistTransactions(itemId: itemId, accountId: accountId, limit: limit)
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
        let generation = SessionLifetime.shared.current
        guard let userId = currentUserId, let persistence = transactionPersistence else {
            return []
        }

        let result = await persistence.loadTransactions(
            for: userId,
            accountId: accountId,
            limit: limit,
            before: before
        )
        guard SessionLifetime.shared.isCurrent(generation), currentUserId == userId else { return [] }
        return result
    }

    /// Fetches transactions for a specific bank item
    /// - Parameters:
    ///   - itemId: The internal bank item UUID
    ///   - forceRefresh: If true, bypasses cache and fetches fresh data
    /// - Returns: Array of transactions for that item
    func fetchTransactionsForItem(itemId: String, forceRefresh: Bool = false) async throws -> [Transaction] {
        let generation = SessionLifetime.shared.current
        guard let userId = currentUserId else {
            throw BankError.unauthorized
        }

        // 1. Check in-memory cache first
        if !forceRefresh, let cached = transactionsByItemId[itemId] {
            // Trigger background refresh if stale
            if let persistence = transactionPersistence,
               await persistence.needsRecentSync(for: userId, itemId: itemId) {
                Task { await backgroundRefreshTransactions(itemId: itemId) }
            }
            try SessionLifetime.shared.check(generation)
            return cached
        }

        // 2. Check persisted cache
        if !forceRefresh, let persistence = transactionPersistence {
            let persisted = await persistence.loadAllTransactions(for: userId, itemId: itemId)

            // Only trust a NON-EMPTY persisted list. An empty one is
            // indistinguishable from a wiped cache (a skipped sync used to
            // persist []), so it goes to the network instead.
            if !persisted.isEmpty {
                try SessionLifetime.shared.check(generation)
                transactionsByItemId[itemId] = persisted
                // Trigger background refresh if stale
                if await persistence.needsRecentSync(for: userId, itemId: itemId) {
                    Task { await backgroundRefreshTransactions(itemId: itemId) }
                }
                try SessionLifetime.shared.check(generation)
                return persisted
            }
        }

        // 3. Fetch from network. Overlapping calls for the same item share
        // one request (two syncs in flight made the backend skip one with an
        // empty list, which then wiped the cache).
        if let inflight = inflightItemFetches[itemId] {
            return try await inflight.value
        }
        isLoadingTransactions = true
        transactionsError = nil
        let task = Task<[Transaction], Error> { [weak self] in
            guard let self else { return [] }
            let fetched = try await self.bankService.getTransactionsForItem(itemId: itemId)
            try SessionLifetime.shared.check(generation)
            return await self.acceptItemTransactions(fetched, itemId: itemId, userId: userId, fullSync: true)
        }
        inflightItemFetches[itemId] = task
        defer {
            if SessionLifetime.shared.isCurrent(generation) {
                inflightItemFetches[itemId] = nil
                isLoadingTransactions = false
            }
        }
        do {
            return try await task.value
        } catch let error as BankError {
            try SessionLifetime.shared.check(generation)
            transactionsError = error
            throw error
        } catch {
            try SessionLifetime.shared.check(generation)
            let bankError = BankError.networkError
            transactionsError = bankError
            throw bankError
        }
    }

    @ObservationIgnored private var inflightItemFetches: [String: Task<[Transaction], Error>] = [:]

    /// Store a fetched per-item list. An EMPTY result never replaces a
    /// non-empty cache (the backend returns [] when a sync is skipped, and
    /// a bank with transactions does not lose them all in one sync).
    private func acceptItemTransactions(_ fetched: [Transaction], itemId: String, userId: String, fullSync: Bool) async -> [Transaction] {
        guard currentUserId == userId, !Task.isCancelled else { return [] }
        let generation = SessionLifetime.shared.current
        let existing = transactionsByItemId[itemId] ?? []
        if fetched.isEmpty && !existing.isEmpty {
            Logger.warning("BankDataManager: empty transaction list for item \(itemId) ignored; keeping \(existing.count) cached")
            return existing
        }
        transactionsByItemId[itemId] = fetched
        if let persistence = transactionPersistence {
            await persistence.saveTransactions(fetched, for: userId, itemId: itemId)
            if fullSync { await persistence.markFullSyncComplete(for: userId, itemId: itemId) }
            await persistence.markRecentSyncComplete(for: userId, itemId: itemId)
        }
        guard SessionLifetime.shared.isCurrent(generation), currentUserId == userId else { return [] }
        lastTransactionSyncAt = Date()
        return fetched
    }

    // MARK: - All accounts (Money tab)

    /// Every account's transactions, newest first. Prefers the single
    /// GET /bank/transactions read; on backends without it, merges the
    /// per-institution lists (forceRefresh runs one sync per item first).
    /// Never returns an empty list while a cached one exists.
    func allTransactions(forceRefresh: Bool, limit: Int = 200) async -> [Transaction] {
        let generation = SessionLifetime.shared.current
        if let inflight = inflightAllFetch { return await inflight.value }
        let task = Task<[Transaction], Never> { [weak self] in
            guard let self else { return [] }
            var result: [Transaction] = []
            if let fetched = try? await self.bankService.getTransactions(accountId: nil, limit: limit, offset: nil), !fetched.isEmpty {
                result = fetched
            } else {
                // One bank's sync used to wait for the previous one; a slow
                // institution made pull-to-refresh take the sum of all three.
                let items = self.linkedItems ?? []
                let merged: [Transaction] = await withTaskGroup(of: [Transaction].self) { group in
                    for item in items {
                        group.addTask { [weak self] in
                            guard let self else { return [] }
                            var txns = (try? await self.fetchTransactionsForItem(itemId: item.itemId, forceRefresh: forceRefresh)) ?? []
                            if txns.isEmpty && !forceRefresh {
                                // Nothing cached for this bank: go to the network once.
                                txns = (try? await self.fetchTransactionsForItem(itemId: item.itemId, forceRefresh: true)) ?? []
                            }
                            return txns
                        }
                    }
                    var all: [Transaction] = []
                    for await part in group { all.append(contentsOf: part) }
                    return all
                }
                var seen = Set<String>()
                result = merged
                    .filter { seen.insert($0.idTransaction).inserted }
                    .sorted { $0.transactionDate > $1.transactionDate }
                    .prefix(limit)
                    .map { $0 }
            }
            guard SessionLifetime.shared.isCurrent(generation), !Task.isCancelled else { return [] }
            if result.isEmpty, let cached = self.transactions, !cached.isEmpty { return cached }
            self.transactions = result
            self.transactionsLastFetched = Date()
            return result
        }
        inflightAllFetch = task
        defer { if SessionLifetime.shared.isCurrent(generation) { inflightAllFetch = nil } }
        return await task.value
    }

    @ObservationIgnored private var inflightAllFetch: Task<[Transaction], Never>?

    /// "TD Bank · Checking ••1234" for a transaction's account, if known.
    func accountLabel(for accountId: String) -> String? {
        for item in linkedItems ?? [] {
            if let acct = accountsByItemId[item.itemId]?.first(where: { $0.idAccount == accountId }) {
                return "\(item.institutionName) · \(acct.name) ••\(acct.mask)"
            }
        }
        return nil
    }

    // MARK: - Background Refresh

    /// Refreshes transactions in background without blocking UI
    /// - Parameter itemId: The internal bank item UUID
    private func backgroundRefreshTransactions(itemId: String) async {
        let generation = SessionLifetime.shared.current
        guard let userId = currentUserId else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            if inflightItemFetches[itemId] != nil { return }
            let fetchedTransactions = try await bankService.getTransactionsForItem(itemId: itemId)
            guard SessionLifetime.shared.isCurrent(generation), !Task.isCancelled else { return }
            _ = await acceptItemTransactions(fetchedTransactions, itemId: itemId, userId: userId, fullSync: false)

            Logger.debug("BankDataManager: Background refresh completed for item \(itemId)")
        } catch {
            Logger.warning("BankDataManager: Background refresh failed: \(error.localizedDescription)")
        }
    }

    /// Fetches transactions from network and persists them
    /// - Parameters:
    ///   - itemId: The internal bank item UUID
    ///   - accountId: The account ID to filter transactions for
    ///   - limit: Maximum number of transactions to return
    private func fetchAndPersistTransactions(
        itemId: String,
        accountId: String,
        limit: Int
    ) async throws -> [Transaction] {
        let generation = SessionLifetime.shared.current
        guard let userId = currentUserId else {
            throw BankError.unauthorized
        }

        isLoadingTransactions = true
        transactionsError = nil
        defer { if SessionLifetime.shared.isCurrent(generation) { isLoadingTransactions = false } }

        do {
            let fetchedTransactions = try await bankService.getTransactionsForItem(itemId: itemId)
            try SessionLifetime.shared.check(generation)
            transactionsByItemId[itemId] = fetchedTransactions

            // Persist for future instant display
            if let persistence = transactionPersistence {
                await persistence.saveTransactions(fetchedTransactions, for: userId, itemId: itemId)
                await persistence.markFullSyncComplete(for: userId, itemId: itemId)
            }

            lastTransactionSyncAt = Date()

            // Filter and return for the requested account
            let filtered = fetchedTransactions.filter { $0.accountId == accountId }
            return Array(filtered.prefix(limit))
        } catch let error as BankError {
            try SessionLifetime.shared.check(generation)
            transactionsError = error
            throw error
        } catch {
            try SessionLifetime.shared.check(generation)
            let bankError = BankError.networkError
            transactionsError = bankError
            throw bankError
        }
    }

    // MARK: - Sync Management

    /// Syncs bank data for a specific bank item
    /// - Parameter itemId: The internal bank item UUID to sync
    func syncBankData(itemId: String) async throws {
        isSyncing = true
        syncError = nil

        do {
            _ = try await bankService.syncBankData(itemId: itemId)

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

    /// Looks up the internal item UUID for a given Plaid item ID
    /// - Parameter plaidItemId: The Plaid item ID to look up
    /// - Returns: The internal item UUID, or nil if not found
    func getItemId(for plaidItemId: String) -> String? {
        linkedItems?.first { $0.plaidItemId == plaidItemId }?.itemId
    }

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

    /// Groups all accounts by institution (internal item ID)
    func accountsGroupedByInstitution() -> [String: [BankAccount]] {
        guard let linkedItems = linkedItems else { return [:] }

        var grouped: [String: [BankAccount]] = [:]
        for item in linkedItems {
            grouped[item.itemId] = accountsByItemId[item.itemId] ?? []
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
        accountsByItemId.values.flatMap { $0 }.reduce(0) { $0 + ($1.currentBalance ?? 0) }
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
        accountsForInstitution(itemId: itemId).reduce(0) { $0 + ($1.currentBalance ?? 0) }
    }
}


extension Notification.Name {
    /// Sign-out (or a different user signing in): every manager drops its data.
    static let userDataCleared = Notification.Name("UserDataCleared")
}
