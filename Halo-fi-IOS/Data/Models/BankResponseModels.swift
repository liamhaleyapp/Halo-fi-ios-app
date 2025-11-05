//
//  BankResponseModels.swift
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

