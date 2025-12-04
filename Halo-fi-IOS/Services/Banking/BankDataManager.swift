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
class BankDataManager {
    // MARK: - State
    
    var accounts: [BankAccount]?
    var transactions: [Transaction]?
    var accountsSummary: BankAccountsResponse?
    
    /// Linked items (institutions) from Plaid - stored after sandbox/production linking
    var linkedItems: [ConnectedItem]?
    
    /// Accounts grouped by item ID - fetched on demand using GET /bank/{item_id}/account
    var accountsByItemId: [String: [BankAccount]] = [:]
    
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
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    
    // MARK: - Dependencies
    
    private let bankService: BankService
    private let tokenStorage: TokenStorage
    
    // MARK: - Initialization
    
    init(bankService: BankService = BankService.shared, tokenStorage: TokenStorage = TokenStorage()) {
        self.bankService = bankService
        self.tokenStorage = tokenStorage
    }
    
    // MARK: - Bank Linking Flow
    
    /// Exchanges collected public tokens for access tokens via backend
    /// - Parameter publicTokens: Array of public tokens from Plaid Link (can be empty for sandbox "continue as guest")
    /// - Parameter useSandbox: If true, uses sandbox endpoint (for testing/guest mode)
    func completeLinking(with publicTokens: [String], useSandbox: Bool = false) async throws -> BankMultiConnectResponse {
        // For sandbox, allow empty public tokens (e.g., "continue as guest" flow)
        let sanitizedTokens = useSandbox ? publicTokens.filter { !$0.isEmpty } : publicTokens
        
        print("🔵 BankDataManager: Connecting bank accounts...")
        print("   - Public tokens count: \(sanitizedTokens.count)")
        print("   - Use sandbox: \(useSandbox)")
        
        let response = try await connectMultipleBankAccounts(publicTokens: sanitizedTokens.isEmpty && useSandbox ? [""] : sanitizedTokens, useSandbox: useSandbox)
        
        print("🔵 BankDataManager: Connection response received")
        print("   - Success: \(response.success)")
        print("   - Message: \(response.message ?? "nil")")
        print("   - Total Items Created: \(response.totalItemsCreated?.description ?? "nil")")
        print("   - Failed Items: \(response.failedItems?.count ?? 0)")
        print("   - All Connected Items: \(response.allConnectedItems?.count ?? 0)")
        
        guard response.success else {
            let message = response.message ?? "Unable to connect bank accounts."
            print("❌ BankDataManager: Connection failed - \(message)")
            throw BankError.multiConnectFailed(message)
        }
        
        print("✅ BankDataManager: Connection successful")
        
        // For sandbox, check totalItemsCreated instead of failedItems
        if useSandbox {
            if let itemsCreated = response.totalItemsCreated, itemsCreated == 0 {
                let message = response.message ?? "No items were created. Please try again."
                throw BankError.multiConnectFailed(message)
            }
            // Sandbox endpoint creates items automatically, success means items were created
        } else {
            // For production, check failedItems
            if let failedItems = response.failedItems, !failedItems.isEmpty {
                let message = response.message ?? "Failed to connect \(failedItems.count) item(s). Please try again."
                throw BankError.multiConnectFailed(message)
            }
            
            // Ensure we have connected items for production
            if let connectedItems = response.allConnectedItems, connectedItems.isEmpty {
                let message = response.message ?? "No items were connected. Please try again."
                throw BankError.multiConnectFailed(message)
            }
        }
        
        // Extract item IDs and sync them to pull account data from Plaid
        guard let connectedItems = response.allConnectedItems, !connectedItems.isEmpty else {
            print("⚠️ BankDataManager: No connected items to sync")
            return response
        }
        
        // Store linked items for later use (e.g., displaying in AccountsView)
        self.linkedItems = connectedItems
        print("✅ BankDataManager: Stored \(connectedItems.count) linked items")
        
        // Use itemId (UUID) not plaidItemId - the sync endpoint expects UUIDs
        let itemIds = connectedItems.map { $0.itemId }
        print("🔵 BankDataManager: Syncing \(itemIds.count) items...")
        print("   - Item IDs (UUIDs): \(itemIds)")
        print("   - Plaid Item IDs: \(connectedItems.map { $0.plaidItemId })")
        
        do {
            let syncResponse = try await bankService.syncMultipleItems(itemIds: itemIds)
            print("✅ BankDataManager: Sync initiated successfully")
            print("   - Success: \(syncResponse.success)")
            print("   - Message: \(syncResponse.message ?? "nil")")
            print("   - Accounts Updated: \(syncResponse.accountsUpdated ?? -1)")
            print("   - Transactions Updated: \(syncResponse.transactionsUpdated ?? -1)")
            
            // If sync is async (202), wait a bit for it to complete
            // Then fetch accounts to get the synced data
            if syncResponse.accountsUpdated == nil {
                // Sync might be async, wait a moment
                print("🔵 BankDataManager: Sync appears to be async, waiting 2 seconds...")
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
            
            // Fetch accounts to update the UI with the newly synced data
            print("🔵 BankDataManager: Fetching accounts after sync...")
            try await fetchAccounts(forceRefresh: true)
        } catch let error as BankError {
            print("⚠️ BankDataManager: Sync failed with BankError: \(error)")
            if case .validationError(let details) = error {
                print("   - Validation errors:")
                for detail in details {
                    print("     → Location: \(detail.loc.joined(separator: "."))")
                    print("       Message: \(detail.msg)")
                    print("       Type: \(detail.type)")
                }
            } else if case .serverError(let code) = error {
                print("   - Server error code: \(code)")
            }
            // Don't fail the entire linking process if sync fails - items are already connected
            // Try to fetch accounts anyway in case they were synced by the backend
            print("🔵 BankDataManager: Attempting to fetch accounts despite sync failure...")
            try? await fetchAccounts(forceRefresh: true)
        } catch {
            print("⚠️ BankDataManager: Sync failed with unknown error: \(error)")
            print("   - Error type: \(type(of: error))")
            print("   - Error description: \(error.localizedDescription)")
            // Don't fail the entire linking process if sync fails - items are already connected
            // Try to fetch accounts anyway in case they were synced by the backend
            print("🔵 BankDataManager: Attempting to fetch accounts despite sync failure...")
            try? await fetchAccounts(forceRefresh: true)
        }
        
        return response
    }
    
    // MARK: - Account Management
    
    /// Fetches bank accounts from the API
    /// - Parameter forceRefresh: If true, bypasses cache and fetches fresh data
    func fetchAccounts(forceRefresh: Bool = false) async throws {
        // Check if we have valid cached data
        if !forceRefresh,
           accounts != nil,
           let lastFetched = accountsLastFetched,
           Date().timeIntervalSince(lastFetched) < cacheTTL {
            // Return cached data
            return
        }
        
        isLoadingAccounts = true
        accountsError = nil
        
        do {
            print("🔵 BankDataManager: Fetching accounts from API...")
            let fetchedAccounts = try await bankService.getBankAccounts()
            
            print("✅ BankDataManager: Accounts fetched successfully")
            print("   - Accounts count: \(fetchedAccounts.count)")
            
            if fetchedAccounts.isEmpty {
                print("⚠️ BankDataManager: Accounts array is empty")
            } else {
                print("   - Account details:")
                for (index, account) in fetchedAccounts.enumerated() {
                  print("     [\(index)] ID: \(account.id), Name: \(account.name), Type: \(account.type), Balance: \(account.currentBalance)")
                }
            }
            
            await MainActor.run {
                self.accounts = fetchedAccounts
                self.accountsLastFetched = Date()
                self.isLoadingAccounts = false
            }
        } catch let error as BankError {
            print("❌ BankDataManager: BankError fetching accounts: \(error)")
            await MainActor.run {
                self.accountsError = error
                self.isLoadingAccounts = false
            }
            throw error
        } catch {
            print("❌ BankDataManager: Unknown error fetching accounts: \(error)")
            let bankError = BankError.networkError
            await MainActor.run {
                self.accountsError = bankError
                self.isLoadingAccounts = false
            }
            throw bankError
        }
    }
    
    /// Fetches the full accounts response including summary data
    func fetchAccountsSummary(forceRefresh: Bool = false) async throws {
        // This will fetch accounts and we can extract summary from the response
        // For now, we'll use the same method but could be enhanced if the API provides a summary endpoint
        try await fetchAccounts(forceRefresh: forceRefresh)
    }
    
    /// Fetches bank accounts for a specific item
    /// - Parameters:
    ///   - itemId: The item ID to fetch accounts for
    /// - Returns: ItemAccountsResponse containing accounts for that item
    /// - Note: Uses `GET /bank/{item_id}/account` endpoint via NetworkService
    func fetchAccountsForItem(itemId: String) async throws -> ItemAccountsResponse {
        print("🔵 BankDataManager: Fetching accounts for item \(itemId)")
        
        do {
            // BankService now uses NetworkService internally which handles authentication
            let response = try await bankService.getAccountsByItemId(itemId: itemId)
            
            print("✅ BankDataManager: Fetched \(response.accounts.count) accounts for item \(itemId)")
            
            if response.accounts.isEmpty {
                print("⚠️ BankDataManager: No accounts found for item \(itemId)")
            } else {
                print("   - Account details:")
                for (index, account) in response.accounts.enumerated() {
                    print("     [\(index)] ID: \(account.id), Name: \(account.name), Type: \(account.type), Balance: \(account.currentBalance)")
                }
            }
            
            return response
        } catch let error as BankError {
            print("❌ BankDataManager: BankError fetching accounts for item \(itemId): \(error)")
            throw error
        } catch {
            print("❌ BankDataManager: Unknown error fetching accounts for item \(itemId): \(error)")
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
        
        do {
            let response: BankMultiConnectResponse
            if useSandbox {
                // Use sandbox endpoint for testing (e.g., "continue as guest" flow)
                response = try await bankService.createSandboxMultiItems(
                    publicTokens: publicTokens
                )
            } else {
                // Use production endpoint
                response = try await bankService.connectMultipleBankAccounts(
                    publicTokens: publicTokens
                )
            }
            isSyncing = false
            return response
        } catch let error as BankError {
            isSyncing = false
            syncError = error
            throw error
        } catch {
            isSyncing = false
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
        // Create cache key based on parameters
        let cacheKey = "\(accountId ?? "all")-\(limit ?? 0)-\(offset ?? 0)"
        
        // Check if we have valid cached data for this query
        if !forceRefresh,
           cacheKey == transactionsCacheKey,
           transactions != nil,
           let lastFetched = transactionsLastFetched,
           Date().timeIntervalSince(lastFetched) < cacheTTL {
            // Return cached data
            return
        }
        
        guard let accessToken = tokenStorage.getAccessToken() else {
            throw BankError.unauthorized
        }
        
        isLoadingTransactions = true
        transactionsError = nil
        
        do {
            let fetchedTransactions = try await bankService.getTransactions(
                accountId: accountId,
                limit: limit,
                offset: offset
            )
            
            await MainActor.run {
                self.transactions = fetchedTransactions
                self.transactionsLastFetched = Date()
                self.transactionsCacheKey = cacheKey
                self.isLoadingTransactions = false
            }
        } catch let error as BankError {
            await MainActor.run {
                self.transactionsError = error
                self.isLoadingTransactions = false
            }
            throw error
        } catch {
            let bankError = BankError.networkError
            await MainActor.run {
                self.transactionsError = bankError
                self.isLoadingTransactions = false
            }
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
            _ = try await bankService.syncBankData(
                plaidItemId: plaidItemId
            )
            
            // After successful sync, refresh accounts and transactions
            await MainActor.run {
                self.isSyncing = false
            }
            
            // Refresh accounts data after sync
            try await fetchAccounts(forceRefresh: true)
            
            // If we have cached transactions, refresh them too
            // Use the same parameters as the last fetch
            if transactionsCacheKey != nil {
                // Parse cache key to get original parameters (simplified - just clear and let user refetch)
                clearTransactionsCache()
            }
        } catch let error as BankError {
            await MainActor.run {
                self.syncError = error
                self.isSyncing = false
            }
            throw error
        } catch {
            let bankError = BankError.networkError
            await MainActor.run {
                self.syncError = bankError
                self.isSyncing = false
            }
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
        return accounts?.first { $0.idAccount == id }
    }
    
    /// Gets transactions for a specific account
    func getTransactions(for accountId: String) -> [Transaction] {
        return transactions?.filter { $0.accountId == accountId } ?? []
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
}

