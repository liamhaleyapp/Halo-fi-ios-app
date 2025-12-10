//
//  BankService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Bank Service
final class BankService: BankServiceProtocol {
    static let shared = BankService()

    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol = NetworkService.shared) {
        self.networkService = networkService
    }
    
    // MARK: - Connect Multiple Bank Accounts
    /// Connects multiple bank accounts using public tokens returned from Plaid Link
    /// - Parameter publicTokens: Array of public tokens from Plaid Link
    /// - Returns: BankMultiConnectResponse with connected items
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func connectMultipleBankAccounts(publicTokens: [String]) async throws -> BankMultiConnectResponse {
        let requestBody = BankMultiConnectRequest(publicTokens: publicTokens)
        let bodyData = try JSONEncoder().encode(requestBody)

        do {
            return try await networkService.authenticatedRequest(
                endpoint: APIEndpoints.Bank.multiConnect,
                method: .POST,
                body: bodyData,
                responseType: BankMultiConnectResponse.self
            )
        } catch {
            throw convertToBankError(error)
        }
    }
    
    // MARK: - Sandbox: Create Multiple Items
    /// Creates multiple sandbox items directly (sandbox/testing only)
    /// - Parameter publicTokens: Array of public tokens (can be empty for sandbox)
    /// - Returns: BankMultiConnectResponse with created items
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func createSandboxMultiItems(publicTokens: [String]) async throws -> BankMultiConnectResponse {
        let requestBody = BankMultiConnectRequest(publicTokens: publicTokens)
        let bodyData = try JSONEncoder().encode(requestBody)

        do {
            return try await networkService.authenticatedRequest(
                endpoint: APIEndpoints.Sandbox.createMultiItems,
                method: .POST,
                body: bodyData,
                responseType: BankMultiConnectResponse.self
            )
        } catch {
            throw convertToBankError(error)
        }
    }
    
    // MARK: - Get Bank Accounts
    /// Fetches all bank accounts for the authenticated user
    /// - Returns: Array of BankAccount objects
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func getBankAccounts() async throws -> [BankAccount] {
        do {
            let response: BankAccountsResponse = try await networkService.authenticatedRequest(
                endpoint: APIEndpoints.Bank.accounts,
                method: .GET,
                body: nil,
                responseType: BankAccountsResponse.self
            )
            return response.accounts
        } catch let authError as AuthError {
            // Return empty array for 404 (no accounts found)
            if case .serverError(let code, _) = authError, code == 404 {
                return []
            }
            throw convertToBankError(authError)
        } catch {
            throw convertToBankError(error)
        }
    }
    
    // MARK: - Get Accounts by Item ID
    /// Fetches bank accounts for a specific Plaid item
    /// - Parameter itemId: The item ID (not plaid_item_id) to fetch accounts for
    /// - Returns: ItemAccountsResponse containing accounts for that item
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func getAccountsByItemId(itemId: String) async throws -> ItemAccountsResponse {
        Logger.info("Fetching accounts for item \(itemId)")

        do {
            let response: ItemAccountsResponse = try await networkService.authenticatedRequest(
                endpoint: APIEndpoints.Bank.accountsForItem(itemId),
                method: .GET,
                body: nil,
                responseType: ItemAccountsResponse.self
            )
            Logger.success("Fetched \(response.accounts.count) accounts for item \(itemId)")
            return response
        } catch let authError as AuthError {
            // Return empty response for 404 (item not found)
            if case .serverError(let code, _) = authError, code == 404 {
                Logger.warning("Item \(itemId) not found (404)")
                return ItemAccountsResponse(accounts: [])
            }
            Logger.error("AuthError fetching accounts for item \(itemId): \(authError)")
            throw convertToBankError(authError)
        } catch {
            Logger.error("Unknown error fetching accounts for item \(itemId): \(error)")
            throw convertToBankError(error)
        }
    }
    
    // MARK: - Get Transactions
    /// Fetches transactions for the authenticated user
    /// - Parameters:
    ///   - accountId: Optional account ID to filter transactions
    ///   - limit: Optional limit on number of transactions to return
    ///   - offset: Optional offset for pagination
    /// - Returns: Array of Transaction objects
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func getTransactions(accountId: String? = nil, limit: Int? = nil, offset: Int? = nil) async throws -> [Transaction] {
        // Build endpoint with query parameters
        var endpoint = APIEndpoints.Bank.transactions
        var queryItems: [URLQueryItem] = []

        if let accountId = accountId {
            queryItems.append(URLQueryItem(name: "account_id", value: accountId))
        }
        if let limit = limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let offset = offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }

        if !queryItems.isEmpty {
            var components = URLComponents(string: endpoint)
            components?.queryItems = queryItems
            if let queryString = components?.url?.query {
                endpoint = "\(endpoint)?\(queryString)"
            }
        }

        do {
            let response: TransactionsResponse = try await networkService.authenticatedRequest(
                endpoint: endpoint,
                method: .GET,
                body: nil,
                responseType: TransactionsResponse.self
            )
            return response.transactions
        } catch {
            throw convertToBankError(error)
        }
    }
    
    // MARK: - Sync Bank Data
    
    /// Syncs multiple bank items at once
    /// - Parameter itemIds: Array of Plaid item IDs to sync
    /// - Returns: BankSyncResponse with sync results
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func syncMultipleItems(itemIds: [String]) async throws -> BankSyncResponse {
        let requestBody = BankMultiItemsSyncRequest(itemIds: itemIds)
        let bodyData = try JSONEncoder().encode(requestBody)

        Logger.info("Syncing \(itemIds.count) items")

        do {
            let response: BankSyncResponse = try await networkService.authenticatedRequest(
                endpoint: APIEndpoints.Bank.multiItemsSync,
                method: .POST,
                body: bodyData,
                responseType: BankSyncResponse.self
            )
            Logger.success("Sync completed successfully")
            return response
        } catch {
            Logger.error("Sync error: \(error)")
            throw convertToBankError(error, notFoundBehavior: .throwItemNotFound)
        }
    }
    
    /// Syncs bank data for a specific Plaid item
    /// - Parameter plaidItemId: The Plaid item ID to sync
    /// - Returns: BankSyncResponse with sync results
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func syncBankData(plaidItemId: String) async throws -> BankSyncResponse {
        do {
            return try await networkService.authenticatedRequest(
                endpoint: APIEndpoints.Bank.syncItem(plaidItemId),
                method: .POST,
                body: nil,
                responseType: BankSyncResponse.self
            )
        } catch {
            throw convertToBankError(error, notFoundBehavior: .throwItemNotFound)
        }
    }
    
    // MARK: - Disconnect Bank Account
    /// Disconnects a bank account by Plaid item ID
    /// - Parameter plaidItemId: The Plaid item ID to disconnect
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func disconnectBankAccount(plaidItemId: String) async throws {
        do {
            // EmptyResponse handles DELETE operations that return no body (200/204)
            let _: EmptyResponse = try await networkService.authenticatedRequest(
                endpoint: APIEndpoints.Bank.disconnect(plaidItemId),
                method: .DELETE,
                body: nil,
                responseType: EmptyResponse.self
            )
        } catch {
            throw convertToBankError(error, notFoundBehavior: .throwItemNotFound)
        }
    }
    
    // MARK: - Bank Health Check
    /// Checks the health status of bank services
    /// - Returns: BankHealthResponse with health status
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func checkBankHealth() async throws -> BankHealthResponse {
        do {
            return try await networkService.authenticatedRequest(
                endpoint: APIEndpoints.Bank.health,
                method: .GET,
                body: nil,
                responseType: BankHealthResponse.self
            )
        } catch {
            throw convertToBankError(error)
        }
    }

    // MARK: - Error Conversion Helper

    /// Converts AuthError or other errors to BankError for consistent API.
    /// - Parameters:
    ///   - error: The error to convert.
    ///   - notFoundBehavior: How to handle 404 errors (default: throw serverError).
    /// - Returns: Never returns normally; always throws a BankError.
    private func convertToBankError(_ error: Error, notFoundBehavior: NotFoundBehavior = .throwServerError) -> BankError {
        guard let authError = error as? AuthError else {
            return .networkError
        }

        switch authError {
        case .networkError:
            return .networkError
        case .tokenExpired, .invalidCredentials:
            return .unauthorized
        case .validationError(let details):
            return .validationError(details)
        case .serverError(let code, _):
            if code == 404 {
                switch notFoundBehavior {
                case .throwServerError:
                    return .serverError(code)
                case .throwItemNotFound:
                    return .itemNotFound
                case .returnEmpty:
                    // Caller handles this case specially
                    return .serverError(code)
                }
            }
            return .serverError(code)
        default:
            return .networkError
        }
    }

    /// Defines how 404 errors should be handled.
    private enum NotFoundBehavior {
        case throwServerError
        case throwItemNotFound
        case returnEmpty
    }
}
