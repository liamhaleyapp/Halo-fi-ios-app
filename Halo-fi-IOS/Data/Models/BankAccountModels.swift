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
    let currentBalance: Double?
    let availableBalance: Double?
    let currency: String
    let idAccount: String
    let plaidItemId: String?
    let plaidAccountId: String
    let isActive: Bool
    let createdAt: String?
    let updatedAt: String?
    /// The user's own name for the account (2026-09-05); nil = the bank's name.
    var nickname: String? = nil
    /// ISO date Plaid last listed this account, set only once it has been
    /// missing for 3+ days (2026-09-06). The balance is frozen from then.
    var staleSince: String? = nil

    var staleSpoken: String? {
        guard let staleSince, let d = ISO8601DateFormatter.dateOnly.date(from: staleSince) else { return nil }
        return d.formatted(.dateTime.month(.wide).day())
    }

    /// What to show and speak: the nickname when set, else the bank's name.
    var displayName: String { (nickname?.isEmpty == false) ? nickname! : name }

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
        case nickname
        case staleSince = "stale_since"
    }
}


extension ISO8601DateFormatter {
    /// "2026-09-05" → Date (no time component).
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
