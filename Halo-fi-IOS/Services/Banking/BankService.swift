//
//  BankService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Bank Service
class BankService {
    static let shared = BankService()
    
    private init() {}
    
    // MARK: - Connect Multiple Bank Accounts
    /// Connects multiple bank accounts using public tokens returned from Plaid Link
    /// - Parameter publicTokens: Array of public tokens from Plaid Link
    /// - Returns: BankMultiConnectResponse with connected items
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func connectMultipleBankAccounts(publicTokens: [String]) async throws -> BankMultiConnectResponse {
        let requestBody = BankMultiConnectRequest(publicTokens: publicTokens)
        let bodyData = try JSONEncoder().encode(requestBody)
        
        do {
            // Use NetworkService for authenticated request with proper error handling
            let response: BankMultiConnectResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: "/bank/multi-connect",
                method: .POST,
                body: bodyData,
                responseType: BankMultiConnectResponse.self
            )
            
            return response
            
        } catch let authError as AuthError {
            // Convert AuthError to BankError for consistency with BankService API
            switch authError {
            case .networkError:
                throw BankError.networkError
            case .tokenExpired, .invalidCredentials:
                throw BankError.unauthorized
            case .validationError(let details):
                throw BankError.validationError(details)
            case .serverError(let code, _):
                throw BankError.serverError(code)
            default:
                throw BankError.networkError
            }
        } catch {
            throw BankError.networkError
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
            // Use NetworkService for authenticated request with proper error handling
            let response: BankMultiConnectResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: "/bank/sandbox/create-multi-items",
                method: .POST,
                body: bodyData,
                responseType: BankMultiConnectResponse.self
            )
            
            return response
            
        } catch let authError as AuthError {
            // Convert AuthError to BankError for consistency with BankService API
            switch authError {
            case .networkError:
                throw BankError.networkError
            case .tokenExpired, .invalidCredentials:
                throw BankError.unauthorized
            case .validationError(let details):
                throw BankError.validationError(details)
            case .serverError(let code, _):
                throw BankError.serverError(code)
            default:
                throw BankError.networkError
            }
        } catch {
            throw BankError.networkError
        }
    }
    
    // MARK: - Get Bank Accounts
    /// Fetches all bank accounts for the authenticated user
    /// - Returns: Array of BankAccount objects
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func getBankAccounts() async throws -> [BankAccount] {
        do {
            // Use NetworkService for authenticated request with proper error handling
            let response: BankAccountsResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: "/bank/accounts",
                method: .GET,
                body: nil,
                responseType: BankAccountsResponse.self
            )
            
            return response.accounts
            
        } catch let authError as AuthError {
            // Convert AuthError to BankError for consistency with BankService API
            switch authError {
            case .networkError:
                throw BankError.networkError
            case .tokenExpired, .invalidCredentials:
                throw BankError.unauthorized
            case .validationError(let details):
                throw BankError.validationError(details)
            case .serverError(let code, _):
                // Check if it's a 404 (no accounts found)
                if code == 404 {
                    return []
                }
                throw BankError.serverError(code)
            default:
                throw BankError.networkError
            }
        } catch {
            throw BankError.networkError
        }
    }
    
    // MARK: - Get Accounts by Item ID
    /// Fetches bank accounts for a specific Plaid item
    /// - Parameter itemId: The item ID (not plaid_item_id) to fetch accounts for
    /// - Returns: ItemAccountsResponse containing accounts for that item
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func getAccountsByItemId(itemId: String) async throws -> ItemAccountsResponse {
        print("🔵 BankService: Fetching accounts for item \(itemId)")
        
        do {
            // Use NetworkService for authenticated request with proper error handling
            let response: ItemAccountsResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: "/bank/\(itemId)/account",
                method: .GET,
                body: nil,
                responseType: ItemAccountsResponse.self
            )
            
            print("✅ BankService: Fetched \(response.accounts.count) accounts for item \(itemId)")
            return response
            
        } catch let authError as AuthError {
            // Convert AuthError to BankError for consistency with BankService API
            print("❌ BankService: AuthError fetching accounts for item \(itemId): \(authError)")
            
            switch authError {
            case .networkError:
                throw BankError.networkError
            case .tokenExpired, .invalidCredentials:
                throw BankError.unauthorized
            case .validationError(let details):
                throw BankError.validationError(details)
            case .serverError(let code, let detail):
                // Check if it's a 404 (item not found)
                if code == 404 {
                    print("⚠️ BankService: Item \(itemId) not found (404)")
                    return ItemAccountsResponse(accounts: [])
                }
                throw BankError.serverError(code)
            default:
                throw BankError.networkError
            }
        } catch {
            // Handle other errors
            print("❌ BankService: Unknown error fetching accounts for item \(itemId): \(error)")
            throw BankError.networkError
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
        var endpoint = "/bank/transactions"
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
            // Use NetworkService for authenticated request with proper error handling
            let response: TransactionsResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: endpoint,
                method: .GET,
                body: nil,
                responseType: TransactionsResponse.self
            )
            
            return response.transactions
            
        } catch let authError as AuthError {
            // Convert AuthError to BankError for consistency with BankService API
            switch authError {
            case .networkError:
                throw BankError.networkError
            case .tokenExpired, .invalidCredentials:
                throw BankError.unauthorized
            case .validationError(let details):
                throw BankError.validationError(details)
            case .serverError(let code, _):
                throw BankError.serverError(code)
            default:
                throw BankError.networkError
            }
        } catch {
            throw BankError.networkError
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
        
        print("🔵 BankService: Syncing \(itemIds.count) items")
        
        do {
            // Use NetworkService for authenticated request with proper error handling
            let response: BankSyncResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: "/bank/multi-items/sync",
                method: .POST,
                body: bodyData,
                responseType: BankSyncResponse.self
            )
            
            print("✅ BankService: Sync completed successfully")
            return response
            
        } catch let authError as AuthError {
            // Convert AuthError to BankError for consistency with BankService API
            print("❌ BankService: Sync error: \(authError)")
            
            switch authError {
            case .networkError:
                throw BankError.networkError
            case .tokenExpired, .invalidCredentials:
                throw BankError.unauthorized
            case .validationError(let details):
                throw BankError.validationError(details)
            case .serverError(let code, _):
                // Check if it's a 404 (item not found)
                if code == 404 {
                    throw BankError.itemNotFound
                }
                throw BankError.serverError(code)
            default:
                throw BankError.networkError
            }
        } catch {
            throw BankError.networkError
        }
    }
    
    /// Syncs bank data for a specific Plaid item
    /// - Parameter plaidItemId: The Plaid item ID to sync
    /// - Returns: BankSyncResponse with sync results
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func syncBankData(plaidItemId: String) async throws -> BankSyncResponse {
        do {
            // Use NetworkService for authenticated request with proper error handling
            let response: BankSyncResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: "/bank/sync/\(plaidItemId)",
                method: .POST,
                body: nil,
                responseType: BankSyncResponse.self
            )
            
            return response
            
        } catch let authError as AuthError {
            // Convert AuthError to BankError for consistency with BankService API
            switch authError {
            case .networkError:
                throw BankError.networkError
            case .tokenExpired, .invalidCredentials:
                throw BankError.unauthorized
            case .validationError(let details):
                throw BankError.validationError(details)
            case .serverError(let code, _):
                // Check if it's a 404 (item not found)
                if code == 404 {
                    throw BankError.itemNotFound
                }
                throw BankError.serverError(code)
            default:
                throw BankError.networkError
            }
        } catch {
            throw BankError.networkError
        }
    }
    
    // MARK: - Disconnect Bank Account
    /// Disconnects a bank account by Plaid item ID
    /// - Parameter plaidItemId: The Plaid item ID to disconnect
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func disconnectBankAccount(plaidItemId: String) async throws {
        do {
            // Use NetworkService for authenticated request with proper error handling
            // EmptyResponse handles DELETE operations that return no body (200/204)
            let _: EmptyResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: "/bank/disconnect/\(plaidItemId)",
                method: .DELETE,
                body: nil,
                responseType: EmptyResponse.self
            )
            
            // Success - no return value needed
            
        } catch let authError as AuthError {
            // Convert AuthError to BankError for consistency with BankService API
            switch authError {
            case .networkError:
                throw BankError.networkError
            case .tokenExpired, .invalidCredentials:
                throw BankError.unauthorized
            case .validationError(let details):
                throw BankError.validationError(details)
            case .serverError(let code, _):
                // Check if it's a 404 (item not found)
                if code == 404 {
                    throw BankError.itemNotFound
                }
                throw BankError.serverError(code)
            default:
                throw BankError.networkError
            }
        } catch {
            throw BankError.networkError
        }
    }
    
    // MARK: - Bank Health Check
    /// Checks the health status of bank services
    /// - Returns: BankHealthResponse with health status
    /// - Note: Uses NetworkService for authenticated requests with proper error handling
    func checkBankHealth() async throws -> BankHealthResponse {
        do {
            // Use NetworkService for authenticated request with proper error handling
            let response: BankHealthResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: "/bank/health",
                method: .GET,
                body: nil,
                responseType: BankHealthResponse.self
            )
            
            return response
            
        } catch let authError as AuthError {
            // Convert AuthError to BankError for consistency with BankService API
            switch authError {
            case .networkError:
                throw BankError.networkError
            case .tokenExpired, .invalidCredentials:
                throw BankError.unauthorized
            case .validationError(let details):
                throw BankError.validationError(details)
            case .serverError(let code, _):
                throw BankError.serverError(code)
            default:
                throw BankError.networkError
            }
        } catch {
            throw BankError.networkError
        }
    }
}
