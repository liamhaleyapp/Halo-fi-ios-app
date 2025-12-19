//
//  PersistedTransaction.swift
//  Halo-fi-IOS
//
//  SwiftData model for persisting transactions locally.
//  Enables instant display on app reopen with background refresh.
//

import Foundation
import SwiftData

@Model
final class PersistedTransaction {
    // MARK: - Primary Key

    /// Composite key for upsert without duplicates: {userId}_{idTransaction}
    @Attribute(.unique) var compositeId: String

    // MARK: - Query Keys (for efficient filtering)

    /// User isolation - ensures transactions don't leak between users
    var userId: String

    /// Plaid item this transaction belongs to
    var plaidItemId: String

    /// Account this transaction belongs to - enables per-account queries
    var plaidAccountId: String

    /// Transaction date as Date for sorting/filtering
    var transactionDate: Date

    // MARK: - Core Display Fields

    /// Original transaction ID from backend
    var idTransaction: String

    /// Transaction amount (negative for debits, positive for credits)
    var amount: Double

    /// Currency code (e.g., "USD")
    var currency: String

    /// Transaction description/name
    var name: String

    /// Merchant name if available
    var merchantName: String?

    /// Whether transaction is still pending
    var pending: Bool

    /// Whether transaction is active
    var isActive: Bool

    /// Merchant logo URL if available
    var logoUrl: String?

    // MARK: - JSON-Encoded Fields (minimal storage)

    /// Category array stored as JSON string
    var categoryJson: String?

    // MARK: - Metadata

    /// Plaid's transaction ID
    var plaidTransactionId: String?

    /// Payment channel (e.g., "online", "in store")
    var paymentChannel: String?

    /// Transaction type
    var transactionType: String?

    /// When this record was last synced from the server
    var lastSyncedAt: Date

    /// Original createdAt from backend
    var createdAt: String

    /// Original updatedAt from backend
    var updatedAt: String

    // MARK: - Initialization

    init(
        from transaction: Transaction,
        userId: String,
        plaidItemId: String,
        plaidAccountId: String
    ) {
        self.compositeId = "\(userId)_\(transaction.idTransaction)"
        self.userId = userId
        self.plaidItemId = plaidItemId
        self.plaidAccountId = plaidAccountId

        // Parse transaction date
        self.transactionDate = Self.parseDate(transaction.transactionDate) ?? Date()

        // Core fields
        self.idTransaction = transaction.idTransaction
        self.amount = transaction.amount
        self.currency = transaction.currency
        self.name = transaction.name
        self.merchantName = transaction.merchantName
        self.pending = transaction.pending
        self.isActive = transaction.isActive
        self.logoUrl = transaction.logoUrl

        // JSON-encoded fields
        if let category = transaction.category {
            self.categoryJson = try? String(data: JSONEncoder().encode(category), encoding: .utf8)
        }

        // Metadata
        self.plaidTransactionId = transaction.plaidTransactionId
        self.paymentChannel = transaction.paymentChannel
        self.transactionType = transaction.transactionType
        self.lastSyncedAt = Date()
        self.createdAt = transaction.createdAt
        self.updatedAt = transaction.updatedAt
    }

    // MARK: - Update

    /// Updates this persisted transaction with new data from the server
    func update(from transaction: Transaction) {
        self.transactionDate = Self.parseDate(transaction.transactionDate) ?? self.transactionDate
        self.amount = transaction.amount
        self.currency = transaction.currency
        self.name = transaction.name
        self.merchantName = transaction.merchantName
        self.pending = transaction.pending
        self.isActive = transaction.isActive
        self.logoUrl = transaction.logoUrl

        if let category = transaction.category {
            self.categoryJson = try? String(data: JSONEncoder().encode(category), encoding: .utf8)
        }

        self.plaidTransactionId = transaction.plaidTransactionId
        self.paymentChannel = transaction.paymentChannel
        self.transactionType = transaction.transactionType
        self.lastSyncedAt = Date()
        self.updatedAt = transaction.updatedAt
    }

    // MARK: - Date Parsing

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func parseDate(_ dateString: String) -> Date? {
        dateFormatter.date(from: dateString)
    }
}
