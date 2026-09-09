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
    var balanceSummary: VerifiedBalanceSummary? = nil
    var investments: InvestmentSummary? = nil
    var identityReviews: [AccountIdentityReview]? = nil

    enum CodingKeys: String, CodingKey {
        case success
        case items
        case totalItems = "total_items"
        case balanceSummary = "balance_summary"
        case investments
        case identityReviews = "identity_reviews"
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
    var nickname: String? = nil
    var plaidAccountId: String? = nil

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case name
        case mask
        case type
        case subtype
        case balance
        case nickname
        case plaidAccountId = "plaid_account_id"
    }

    /// Convert to full BankAccount model
    func toBankAccount(plaidItemId: String) -> BankAccount {
        var account = BankAccount(
            name: name,
            mask: mask,
            type: type,
            subtype: subtype,
            currentBalance: balance ?? 0,
            availableBalance: balance ?? 0,  // Use same as current since not provided
            currency: "USD",  // Default, not provided in embedded response
            idAccount: accountId,
            plaidItemId: plaidItemId,
            plaidAccountId: plaidAccountId ?? accountId,
            isActive: true,
            createdAt: nil,
            updatedAt: nil
        )
        account.nickname = nickname
        return account
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

/// The same integer-cent calculation and account breakdown used by voice.
struct VerifiedBalanceSummary: Codable {
    let cashCents: Int
    let owedCents: Int
    let accounts: [Entry]
    let currency: String
    var identityReviews: [AccountIdentityReview]? = nil
    struct Entry: Codable {
        let kind: String
        let cents: Int
    }
    var isValid: Bool {
        currency == "USD" && cashCents == accounts.filter { $0.kind == "cash" }.reduce(0) { $0 + $1.cents }
            && owedCents == accounts.filter { $0.kind == "owed" }.reduce(0) { $0 + $1.cents }
    }
    enum CodingKeys: String, CodingKey {
        case cashCents = "cash_cents", owedCents = "owed_cents", accounts, currency
        case identityReviews = "identity_reviews"
    }
}


struct AccountIdentityReview: Codable, Identifiable {
    let accountId: String
    let name: String
    let mask: String
    let institution: String
    let candidates: [Candidate]
    var itemId: String? = nil
    var plaidAccountId: String? = nil
    var id: String { accountId }
    enum CodingKeys: String, CodingKey {
        case accountId = "account_id", name, mask, institution, candidates
        case itemId = "item_id"
        case plaidAccountId = "plaid_account_id"
    }
    struct Candidate: Codable, Identifiable {
        let accountId: String
        let name: String
        let mask: String
        let institution: String
        var id: String { accountId }
        enum CodingKeys: String, CodingKey {
            case accountId = "account_id", name, mask, institution
        }
    }
}


struct InvestmentSummary: Codable {
    let accounts: [Account]
    let totalCents: Int?
    let currency: String
    let complete: Bool
    var linkedAccountCount: Int? = nil
    enum CodingKeys: String, CodingKey { case accounts, totalCents = "total_cents", currency, complete, linkedAccountCount = "linked_account_count" }
    struct Account: Codable, Identifiable {
        let accountId: String
        let name: String
        let institution: String
        let mask: String
        let currency: String
        let balanceCents: Int?
        let asOf: String?
        let holdings: [Holding]
        var source: String? = nil
        var id: String { accountId }
        enum CodingKeys: String, CodingKey { case accountId = "account_id", name, institution, mask, currency, balanceCents = "balance_cents", asOf = "as_of", holdings, source }
    }
    struct Holding: Codable, Identifiable {
        let id: String
        let name: String
        let ticker: String?
        let quantity: Double
        let valueCents: Int
        let currency: String
        let asOf: String?
        enum CodingKeys: String, CodingKey { case id, name, ticker, quantity, valueCents = "value_cents", currency, asOf = "as_of" }
    }
    static func money(_ cents: Int, currency: String) -> String {
        (Double(cents) / 100).formatted(.currency(code: currency))
    }
}

/// Account values are the portfolio total; holdings must never be added again.
struct InvestmentAllocation {
    struct Segment: Identifiable {
        let id: String
        let label: String
        let cents: Int
    }
    static func total(_ amounts: [Int]) -> Int? {
        var result = 0
        for amount in amounts {
            let next = result.addingReportingOverflow(amount)
            guard !next.overflow else { return nil }
            result = next.partialValue
        }
        return result
    }
    static func segments(_ values: [Segment], limit: Int = 5) -> [Segment] {
        guard limit > 0, values.allSatisfy({ $0.cents >= 0 }), total(values.map(\.cents)) != nil else { return [] }
        let ordered = values.filter { $0.cents > 0 }.sorted {
            $0.cents == $1.cents ? $0.id < $1.id : $0.cents > $1.cents
        }
        guard ordered.count > limit else { return ordered }
        let remainder = Array(ordered.dropFirst(limit))
        return Array(ordered.prefix(limit)) + [.init(id: "allocation-other", label: "Other (\(remainder.count))", cents: total(remainder.map(\.cents))!)]
    }
}

extension InvestmentSummary {
    var verifiedTotalCents: Int? {
        guard complete, accounts.allSatisfy({ $0.balanceCents != nil && $0.currency == currency }),
              let sum = InvestmentAllocation.total(accounts.compactMap(\.balanceCents)), sum == totalCents else { return nil }
        return sum
    }
    var allocation: [InvestmentAllocation.Segment] {
        guard verifiedTotalCents != nil else { return [] }
        return InvestmentAllocation.segments(accounts.map { .init(id: $0.id, label: $0.displayName, cents: $0.balanceCents!) })
    }
    var sortedAccounts: [Account] {
        accounts.sorted {
            if $0.displayName != $1.displayName { return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            return $0.id < $1.id
        }
    }
}

extension InvestmentSummary.Account {
    var displayName: String { "\(institution) · \(name)" + (mask.isEmpty ? "" : " · \(mask)") }
    var spokenName: String { "\(institution), \(name)" + (mask.isEmpty ? "" : ", ending in \(mask)") }
    var formattedBalance: String { balanceCents.map { InvestmentSummary.money($0, currency: currency) } ?? "Balance unavailable" }
    var holdingsAllocation: [InvestmentAllocation.Segment] {
        guard holdings.allSatisfy({ $0.currency == currency }) else { return [] }
        return InvestmentAllocation.segments(holdings.map { .init(id: $0.id, label: $0.ticker ?? $0.name, cents: $0.valueCents) })
    }
}
