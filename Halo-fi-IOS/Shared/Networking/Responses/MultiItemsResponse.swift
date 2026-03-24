//
//  MultiItemsResponse.swift
//  Halo-fi-IOS
//
//  Response model for GET /bank/multi-items endpoint.
//  Decoupled from ConnectedItem to isolate backend changes.
//

import Foundation

/// Response from GET /bank/multi-items endpoint
struct MultiItemsResponse: Codable {
    let success: Bool
    let items: [ServerLinkedItem]
    let totalItems: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case items
        case totalItems = "total_items"
    }
}

/// Server representation of a linked Plaid item
/// Decoupled from ConnectedItem to isolate backend shape changes
struct ServerLinkedItem: Codable {
    let itemId: String
    let plaidItemId: String
    let institutionName: String
    let institutionId: String
    let accountsCount: Int?
    let lastSynced: String?
    let isActive: Bool?
    let availableProductsRaw: String?  // Server sends JSON-encoded string
    let createdAt: String?
    let updatedAt: String?
    let totalBalance: Double?
    let accounts: [ServerEmbeddedAccount]?  // Embedded accounts from multi-items response

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case plaidItemId = "plaid_item_id"
        case institutionName = "institution_name"
        case institutionId = "institution_id"
        case accountsCount = "accounts_count"
        case lastSynced = "last_synced"
        case isActive = "is_active"
        case availableProductsRaw = "available_products"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case totalBalance = "total_balance"
        case accounts
    }

    /// Parsed available products from JSON-encoded string
    var availableProducts: [String]? {
        guard let raw = availableProductsRaw,
              let data = raw.data(using: .utf8),
              let products = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return products
    }
}

/// Embedded account from multi-items response (simpler shape than full BankAccount)
struct ServerEmbeddedAccount: Codable {
    let accountId: String
    let name: String
    let mask: String
    let type: String
    let subtype: String
    let balance: Double?

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case name
        case mask
        case type
        case subtype
        case balance
    }

    /// Convert to full BankAccount model
    func toBankAccount(plaidItemId: String) -> BankAccount {
        BankAccount(
            name: name,
            mask: mask,
            type: type,
            subtype: subtype,
            currentBalance: balance ?? 0,
            availableBalance: balance ?? 0,  // Use same as current since not provided
            currency: "USD",  // Default, not provided in embedded response
            idAccount: accountId,
            plaidItemId: plaidItemId,
            plaidAccountId: accountId,  // Use accountId as plaidAccountId
            isActive: true,
            createdAt: nil,
            updatedAt: nil
        )
    }
}

// MARK: - Mapping to App Model

extension ConnectedItem {
    /// Initialize from server response model
    init(from server: ServerLinkedItem) {
        self.init(
            institutionId: server.institutionId,
            institutionName: server.institutionName,
            availableProducts: server.availableProducts,
            itemId: server.itemId,
            userId: "",  // Not provided by this endpoint, set in DataManager
            plaidItemId: server.plaidItemId,
            isActive: server.isActive ?? true,
            lastSync: server.lastSynced,
            createdAt: server.createdAt,
            updatedAt: server.updatedAt
        )
    }

    /// Helper to apply userId without reconstructing entire model
    func withUserId(_ userId: String) -> ConnectedItem {
        ConnectedItem(
            institutionId: institutionId,
            institutionName: institutionName,
            availableProducts: availableProducts,
            itemId: itemId,
            userId: userId,
            plaidItemId: plaidItemId,
            isActive: isActive,
            lastSync: lastSync,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
