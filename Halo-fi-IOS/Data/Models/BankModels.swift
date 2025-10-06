//
//  BankModels.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Bank Connect Response
struct BankConnectResponse: Codable {
    let institutionId: String
    let institutionName: String
    let availableProducts: [String]
    let idItem: String
    let userId: String
    let plaidItemId: String
    let isActive: Bool
    let lastSync: String
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case institutionId = "institution_id"
        case institutionName = "institution_name"
        case availableProducts = "available_products"
        case idItem = "id_item"
        case userId = "user_id"
        case plaidItemId = "plaid_item_id"
        case isActive = "is_active"
        case lastSync = "last_sync"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Bank Account
struct BankAccount: Codable, Identifiable {
    let id: String
    let name: String
    let type: String
    let subtype: String?
    let mask: String?
    let balance: Double?
    let currency: String?
    let institutionName: String?
    let institutionId: String?
    let plaidItemId: String?
    let createdAt: String
    let updatedAt: String
}

// MARK: - Bank Accounts Response
struct BankAccountsResponse: Codable {
    let accounts: [BankAccount]
    let total: Int
}

// MARK: - Transaction
struct Transaction: Codable, Identifiable {
    let id: String
    let accountId: String
    let amount: Double
    let currency: String
    let description: String?
    let merchantName: String?
    let category: [String]?
    let subcategory: [String]?
    let date: String
    let pending: Bool
    let accountOwner: String?
    let transactionType: String?
    let plaidTransactionId: String?
    let createdAt: String
    let updatedAt: String
}

// MARK: - Transactions Response
struct TransactionsResponse: Codable {
    let transactions: [Transaction]
    let total: Int
    let hasMore: Bool?
}

// MARK: - Bank Sync Response
struct BankSyncResponse: Codable {
    let success: Bool
    let message: String?
    let accountsUpdated: Int?
    let transactionsUpdated: Int?
    let requestId: String?
}

// MARK: - Bank Health Response
struct BankHealthResponse: Codable {
    let status: String
    let message: String?
    let timestamp: String
    let services: [String: String]?
}

// MARK: - Bank Error
enum BankError: LocalizedError {
    case networkError
    case unauthorized
    case validationError([ValidationErrorDetail])
    case itemNotFound
    case serverError(Int)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection error. Please check your internet connection."
        case .unauthorized:
            return "Authentication required. Please sign in again."
        case .validationError(let details):
            let errorMessages = details.map { $0.msg }.joined(separator: ", ")
            return "Validation error: \(errorMessages)"
        case .itemNotFound:
            return "Bank account or item not found."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .invalidResponse:
            return "Invalid response from server."
        }
    }
}
