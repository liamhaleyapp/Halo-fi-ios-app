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
    // Sandbox-specific fields
    let items: [SandboxItem]?
    let publicTokens: [SandboxPublicToken]?
    let accessTokens: [String]?
    let totalItemsCreated: Int?
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case connectedItems = "connected_items"
        case failedItems = "failed_items"
        case items
        case publicTokens = "public_tokens"
        case accessTokens = "access_tokens"
        case totalItemsCreated = "total_items_created"
    }
    
    // Computed property to get items from either structure
    var allConnectedItems: [ConnectedItem]? {
        // Check production format first
        if let connectedItems = connectedItems, !connectedItems.isEmpty {
            return connectedItems
        }
        
        // Map sandbox items to ConnectedItem format
        guard let sandboxItems = items, !sandboxItems.isEmpty else {
            return nil
        }
        
        let mappedItems = sandboxItems.compactMap { sandboxItem -> ConnectedItem? in
            let item = ConnectedItem(
                institutionId: sandboxItem.institutionId,
                institutionName: sandboxItem.institutionName,
                availableProducts: parseAvailableProducts(sandboxItem.availableProducts),
                itemId: sandboxItem.itemId,
                userId: "", // Not provided in sandbox response
                plaidItemId: sandboxItem.plaidItemId,
                isActive: true, // Assume active for sandbox
                lastSync: nil,
                createdAt: sandboxItem.createdAt,
                updatedAt: nil
            )
            return item
        }
        
        return mappedItems.isEmpty ? nil : mappedItems
    }
    
    private func parseAvailableProducts(_ productsString: String?) -> [String]? {
        guard let productsString = productsString else { return nil }
        // Parse JSON array string like: "[\"assets\", \"balance\", ...]"
        guard let data = productsString.data(using: .utf8),
              let products = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return products
    }
}

// Sandbox-specific item structure
struct SandboxItem: Codable {
    let itemId: String
    let plaidItemId: String
    let institutionName: String
    let institutionId: String
    let availableProducts: String? // JSON string array
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case plaidItemId = "plaid_item_id"
        case institutionName = "institution_name"
        case institutionId = "institution_id"
        case availableProducts = "available_products"
        case createdAt = "created_at"
    }
}

struct SandboxPublicToken: Codable {
    let institutionId: String
    let publicToken: String
    let success: Bool
    
    enum CodingKeys: String, CodingKey {
        case institutionId = "institution_id"
        case publicToken = "public_token"
        case success
    }
}

struct ConnectedItem: Codable, Hashable, Identifiable {
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

    var id: String { plaidItemId }
    
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
