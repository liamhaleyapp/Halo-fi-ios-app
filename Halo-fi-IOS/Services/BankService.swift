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
    
    private let baseURL = "https://halofiapp-production.up.railway.app"
    private let session = URLSession.shared
    
    private init() {}
    
    // MARK: - Connect Bank Account
    func connectBankAccount(accessToken: String, publicToken: String) async throws -> BankConnectResponse {
        guard let url = URL(string: "\(baseURL)/bank/connect?public_token=\(publicToken)") else {
            throw BankError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BankError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200, 201:
            let connectResponse = try JSONDecoder().decode(BankConnectResponse.self, from: data)
            return connectResponse
        case 401:
            throw BankError.unauthorized
        case 422:
            let validationError = try JSONDecoder().decode(ValidationError.self, from: data)
            throw BankError.validationError(validationError.detail)
        default:
            throw BankError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Connect Multiple Bank Accounts
    func connectMultipleBankAccounts(accessToken: String, publicTokens: [String]) async throws -> BankMultiConnectResponse {
        guard let url = URL(string: "\(baseURL)/bank/multi-connect") else {
            throw BankError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = BankMultiConnectRequest(publicTokens: publicTokens)
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BankError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200, 201:
            return try JSONDecoder().decode(BankMultiConnectResponse.self, from: data)
        case 401:
            throw BankError.unauthorized
        case 422:
            let validationError = try JSONDecoder().decode(ValidationError.self, from: data)
            throw BankError.validationError(validationError.detail)
        default:
            throw BankError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Get Bank Accounts
    func getBankAccounts(accessToken: String) async throws -> [BankAccount] {
        let url = URL(string: "\(baseURL)/bank/accounts")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BankError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200:
            let accountsResponse = try JSONDecoder().decode(BankAccountsResponse.self, from: data)
            return accountsResponse.accounts
        case 401:
            throw BankError.unauthorized
        default:
            throw BankError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Get Transactions
    func getTransactions(accessToken: String, accountId: String? = nil, limit: Int? = nil, offset: Int? = nil) async throws -> [Transaction] {
        var urlComponents = URLComponents(string: "\(baseURL)/bank/transactions")!
        
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
            urlComponents.queryItems = queryItems
        }
        
        guard let url = urlComponents.url else {
            throw BankError.networkError
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BankError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200:
            let transactionsResponse = try JSONDecoder().decode(TransactionsResponse.self, from: data)
            return transactionsResponse.transactions
        case 401:
            throw BankError.unauthorized
        default:
            throw BankError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Sync Bank Data
    func syncBankData(accessToken: String, plaidItemId: String) async throws -> BankSyncResponse {
        let url = URL(string: "\(baseURL)/bank/sync/\(plaidItemId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BankError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200, 202:
            let syncResponse = try JSONDecoder().decode(BankSyncResponse.self, from: data)
            return syncResponse
        case 401:
            throw BankError.unauthorized
        case 404:
            throw BankError.itemNotFound
        default:
            throw BankError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Disconnect Bank Account
    func disconnectBankAccount(accessToken: String, plaidItemId: String) async throws {
        let url = URL(string: "\(baseURL)/bank/disconnect/\(plaidItemId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BankError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200, 204:
            return // Success
        case 401:
            throw BankError.unauthorized
        case 404:
            throw BankError.itemNotFound
        default:
            throw BankError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Bank Health Check
    func checkBankHealth(accessToken: String) async throws -> BankHealthResponse {
        let url = URL(string: "\(baseURL)/bank/health")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BankError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200:
            let healthResponse = try JSONDecoder().decode(BankHealthResponse.self, from: data)
            return healthResponse
        case 401:
            throw BankError.unauthorized
        default:
            throw BankError.serverError(httpResponse.statusCode)
        }
    }
}
