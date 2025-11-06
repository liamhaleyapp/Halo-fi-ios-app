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
    
    // MARK: - Account Management
    
    /// Fetches bank accounts from the API
    /// - Parameter forceRefresh: If true, bypasses cache and fetches fresh data
    func fetchAccounts(forceRefresh: Bool = false) async throws {
        // Check if we have valid cached data
        if !forceRefresh,
           let cachedAccounts = accounts,
           let lastFetched = accountsLastFetched,
           Date().timeIntervalSince(lastFetched) < cacheTTL {
            // Return cached data
            return
        }
        
        guard let accessToken = tokenStorage.getAccessToken() else {
            throw BankError.unauthorized
        }
        
        isLoadingAccounts = true
        accountsError = nil
        
        do {
            let fetchedAccounts = try await bankService.getBankAccounts(accessToken: accessToken)
            
            await MainActor.run {
                self.accounts = fetchedAccounts
                self.accountsLastFetched = Date()
                self.isLoadingAccounts = false
            }
        } catch let error as BankError {
            await MainActor.run {
                self.accountsError = error
                self.isLoadingAccounts = false
            }
            throw error
        } catch {
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
           let cachedTransactions = transactions,
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
                accessToken: accessToken,
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
        guard let accessToken = tokenStorage.getAccessToken() else {
            throw BankError.unauthorized
        }
        
        isSyncing = true
        syncError = nil
        
        do {
            _ = try await bankService.syncBankData(
                accessToken: accessToken,
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

