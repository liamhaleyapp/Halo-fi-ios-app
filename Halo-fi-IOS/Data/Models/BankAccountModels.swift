//
//  BankAccountModels.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Bank Account
struct BankAccount: Codable, Identifiable {
    let name: String
    let mask: String
    let type: String
    let subtype: String
    let currentBalance: Double
    let availableBalance: Double
    let currency: String
    let idAccount: String
    let plaidItemId: String
    let plaidAccountId: String
    let isActive: Bool
    let createdAt: String
    let updatedAt: String
    
    var id: String {
        return idAccount
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case mask
        case type
        case subtype
        case currentBalance = "current_balance"
        case availableBalance = "available_balance"
        case currency
        case idAccount = "id_account"
        case plaidItemId = "plaid_item_id"
        case plaidAccountId = "plaid_account_id"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Bank Accounts Response
struct BankAccountsResponse: Codable {
    let totalAccounts: Int
    let totalBalance: Double
    let currency: String
    let lastSync: String?  // Optional because API can return null when no sync has occurred yet
    let accounts: [BankAccount]
    
    enum CodingKeys: String, CodingKey {
        case totalAccounts = "total_accounts"
        case totalBalance = "total_balance"
        case currency
        case lastSync = "last_sync"
        case accounts
    }
}

