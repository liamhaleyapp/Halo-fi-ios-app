//
//  BankAccountsResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

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


