//
//  BankMultiConnectResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/10/25.
//

import Foundation

struct BankMultiConnectResponse: Codable {
    let success: Bool
    let message: String?
    let connectedItems: [ConnectedItem]?
    let failedItems: [FailedItem]?
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case connectedItems = "connected_items"
        case failedItems = "failed_items"
    }
}

struct ConnectedItem: Codable {
    let institutionId: String
    let institutionName: String
    let availableProducts: [String]?
    let itemId: String
    let userId: String
    let plaidItemId: String
    let isActive: Bool
    let lastSync: String?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case institutionId = "institution_id"
        case institutionName = "institution_name"
        case availableProducts = "available_products"
        case itemId = "id_item"
        case userId = "user_id"
        case plaidItemId = "plaid_item_id"
        case isActive = "is_active"
        case lastSync = "last_sync"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FailedItem: Codable {
    let code: Int?
    let message: String?
    let details: [String: AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case code
        case message
        case details
    }
}

