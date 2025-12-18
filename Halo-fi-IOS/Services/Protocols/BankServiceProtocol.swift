//
//  BankServiceProtocol.swift
//  Halo-fi-IOS
//
//  Protocol for banking service operations.
//

import Foundation

/// Protocol defining banking service operations.
/// Enables dependency injection and mocking for tests.
protocol BankServiceProtocol {
    /// Connects multiple bank accounts using Plaid Link public tokens.
    /// - Parameter publicTokens: Array of public tokens from Plaid Link
    /// - Returns: Response containing connected items
    func connectMultipleBankAccounts(publicTokens: [String]) async throws -> BankMultiConnectResponse

    /// Creates sandbox items for testing (sandbox environment only).
    /// - Parameter publicTokens: Array of public tokens (can be empty for sandbox)
    /// - Returns: Response containing created items
    func createSandboxMultiItems(publicTokens: [String]) async throws -> BankMultiConnectResponse

    /// Fetches all bank accounts for the authenticated user.
    /// - Returns: Array of bank accounts
    func getBankAccounts() async throws -> [BankAccount]

    /// Fetches accounts for a specific Plaid item.
    /// - Parameter itemId: The item ID to fetch accounts for
    /// - Returns: Response containing accounts for that item
    func getAccountsByItemId(itemId: String) async throws -> ItemAccountsResponse

    /// Fetches transactions for the authenticated user.
    /// - Parameters:
    ///   - accountId: Optional account ID to filter transactions
    ///   - limit: Optional limit on number of transactions
    ///   - offset: Optional offset for pagination
    /// - Returns: Array of transactions
    func getTransactions(accountId: String?, limit: Int?, offset: Int?) async throws -> [Transaction]

    /// Fetches transactions for a specific Plaid item.
    /// - Parameter plaidItemId: The Plaid item ID to fetch transactions for
    /// - Returns: Array of transactions for that item
    func getTransactionsForItem(plaidItemId: String) async throws -> [Transaction]

    /// Syncs bank data for multiple items at once.
    /// - Parameter itemIds: Array of item IDs to sync
    /// - Returns: Response with sync results
    func syncMultipleItems(itemIds: [String]) async throws -> BankSyncResponse

    /// Syncs bank data for a specific Plaid item.
    /// - Parameter plaidItemId: The Plaid item ID to sync
    /// - Returns: Response with sync results
    func syncBankData(plaidItemId: String) async throws -> BankSyncResponse

    /// Disconnects a bank account.
    /// - Parameter plaidItemId: The Plaid item ID to disconnect
    func disconnectBankAccount(plaidItemId: String) async throws

    /// Checks the health status of bank services.
    /// - Returns: Health status response
    func checkBankHealth() async throws -> BankHealthResponse
}

// MARK: - Default Parameters Extension

extension BankServiceProtocol {
    func getTransactions(
        accountId: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> [Transaction] {
        try await getTransactions(accountId: accountId, limit: limit, offset: offset)
    }
}

// MARK: - Mock Implementation for Testing

#if DEBUG
/// Mock banking service for unit tests and previews.
actor MockBankService: BankServiceProtocol {
    var mockAccounts: [BankAccount] = []
    var mockTransactions: [Transaction] = []
    var shouldSucceed = true

    func connectMultipleBankAccounts(publicTokens: [String]) async throws -> BankMultiConnectResponse {
        guard shouldSucceed else { throw BankError.networkError }
        return try decodeMockJSON("""
            {"success": true, "message": "Mock connection", "connectedItems": []}
            """)
    }

    func createSandboxMultiItems(publicTokens: [String]) async throws -> BankMultiConnectResponse {
        guard shouldSucceed else { throw BankError.networkError }
        return try decodeMockJSON("""
            {"success": true, "message": "Mock sandbox items", "connectedItems": []}
            """)
    }

    func getBankAccounts() async throws -> [BankAccount] {
        guard shouldSucceed else { throw BankError.networkError }
        return mockAccounts
    }

    func getAccountsByItemId(itemId: String) async throws -> ItemAccountsResponse {
        guard shouldSucceed else { throw BankError.networkError }
        return try decodeMockJSON("""
            {"accounts": []}
            """)
    }

    func getTransactions(accountId: String?, limit: Int?, offset: Int?) async throws -> [Transaction] {
        guard shouldSucceed else { throw BankError.networkError }
        return mockTransactions
    }

    func getTransactionsForItem(plaidItemId: String) async throws -> [Transaction] {
        guard shouldSucceed else { throw BankError.networkError }
        return mockTransactions
    }

    func syncMultipleItems(itemIds: [String]) async throws -> BankSyncResponse {
        guard shouldSucceed else { throw BankError.networkError }
        return try decodeMockJSON("""
            {"success": true, "message": "Mock sync"}
            """)
    }

    func syncBankData(plaidItemId: String) async throws -> BankSyncResponse {
        guard shouldSucceed else { throw BankError.networkError }
        return try decodeMockJSON("""
            {"success": true, "message": "Mock sync"}
            """)
    }

    func disconnectBankAccount(plaidItemId: String) async throws {
        guard shouldSucceed else { throw BankError.networkError }
    }

    func checkBankHealth() async throws -> BankHealthResponse {
        guard shouldSucceed else { throw BankError.networkError }
        return try decodeMockJSON("""
            {"status": "healthy", "timestamp": "2025-01-01T00:00:00Z"}
            """)
    }

    private func decodeMockJSON<T: Decodable>(_ json: String) throws -> T {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
#endif
