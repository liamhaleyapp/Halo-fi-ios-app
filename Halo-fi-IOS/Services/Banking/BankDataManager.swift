//
//  BankDataManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/5/25.
//

import Foundation
import SwiftUI

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
    private var currentUserId: String?

    // MARK: - Initialization

    init(bankService: BankServiceProtocol = BankService.shared) {
        self.bankService = bankService
    }

    // MARK: - User Session Management

    /// Call after auth resolves with valid user
    func configureForUser(userId: String) {
        currentUserId = userId
        restoreLinkedItems()
        Task {
            await refreshIfStale()
        }
    }

    private func restoreLinkedItems() {
        guard let userId = currentUserId else { return }

        if let items = persistence.load(for: userId) {
            linkedItems = items
            Logger.info("BankDataManager: Restored \(items.count) linked items from persistence")
        } else {
            linkedItems = nil
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

        let lastRefresh = persistence.getLastRefreshAt(for: userId)
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < refreshThreshold {
            Logger.debug("BankDataManager: Skipping refresh - last refresh was recent")
            return
        }

        await refreshAllAccounts(for: userId)
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
        accountsError = nil
        transactionsError = nil
        syncError = nil
        persistence.clear(for: userId)
        currentUserId = nil
        Logger.info("BankDataManager: Cleared all bank data")
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

    /// Fetches transactions for a specific Plaid item
    /// - Parameters:
    ///   - plaidItemId: The Plaid item ID to fetch transactions for
    ///   - forceRefresh: If true, bypasses cache and fetches fresh data
    /// - Returns: Array of transactions for that item
    func fetchTransactionsForItem(plaidItemId: String, forceRefresh: Bool = false) async throws -> [Transaction] {
        // Check cache first
        if !forceRefresh, let cached = transactionsByItemId[plaidItemId] {
            return cached
        }

        isLoadingTransactions = true
        transactionsError = nil
        defer { isLoadingTransactions = false }

        do {
            let fetchedTransactions = try await bankService.getTransactionsForItem(plaidItemId: plaidItemId)
            transactionsByItemId[plaidItemId] = fetchedTransactions
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
