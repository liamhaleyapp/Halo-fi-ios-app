//
//  ItemAccountsResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/4/25.
//

import Foundation

/// Response from `GET /bank/{item_id}/account` endpoint
/// Returns an array of accounts for a specific Plaid item
/// 
/// The API returns accounts directly as an array:
/// ```json
/// [
///   {
///     "name": "string",
///     "mask": "string",
///     "type": "string",
///     "subtype": "string",
///     "current_balance": 0,
///     "available_balance": 0,
///     "currency": "USD",
///     "id_account": "uuid",
///     "plaid_item_id": "uuid",
///     "plaid_account_id": "string",
///     "is_active": true,
///     "created_at": "2025-12-04T20:36:46.757Z",
///     "updated_at": "2025-12-04T20:36:46.757Z"
///   }
/// ]
/// ```
struct ItemAccountsResponse: Codable {
    let accounts: [BankAccount]
    
    /// Custom decoder to handle array response directly from API
    /// The API returns `[BankAccount]` directly, not a wrapped object
    init(from decoder: Decoder) throws {
        // Try to decode as array directly (API returns array)
        if let accountsArray = try? [BankAccount](from: decoder) {
            self.accounts = accountsArray
        } else {
            // Fallback: Try to decode as object with "accounts" key
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.accounts = try container.decode([BankAccount].self, forKey: .accounts)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accounts, forKey: .accounts)
    }
    
    enum CodingKeys: String, CodingKey {
        case accounts
    }
    
    init(accounts: [BankAccount]) {
        self.accounts = accounts
    }
}

