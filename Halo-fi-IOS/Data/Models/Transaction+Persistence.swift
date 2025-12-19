//
//  Transaction+Persistence.swift
//  Halo-fi-IOS
//
//  Extension for converting between Transaction and PersistedTransaction.
//

import Foundation

extension PersistedTransaction {
    /// Converts this persisted transaction back to a Transaction struct
    /// Note: Some fields may be nil as we only persist what's needed for display
    func toTransaction() -> Transaction {
        // Decode category from JSON
        var category: [String]?
        if let json = categoryJson, let data = json.data(using: .utf8) {
            category = try? JSONDecoder().decode([String].self, from: data)
        }

        // Format date back to string
        let dateString = Self.dateFormatter.string(from: transactionDate)

        // Create Transaction using struct-based factory to avoid init conflicts
        let data = PersistedTransactionData(
            amount: amount,
            currency: currency,
            transactionDate: dateString,
            name: name,
            merchantName: merchantName,
            category: category,
            pending: pending,
            paymentChannel: paymentChannel,
            transactionType: transactionType,
            logoUrl: logoUrl,
            idTransaction: idTransaction,
            accountId: plaidAccountId,
            plaidTransactionId: plaidTransactionId,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        return Transaction.fromPersisted(data)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

// MARK: - Transaction Factory

/// Container for persisted transaction data
struct PersistedTransactionData {
    let amount: Double
    let currency: String
    let transactionDate: String
    let name: String
    let merchantName: String?
    let category: [String]?
    let pending: Bool
    let paymentChannel: String?
    let transactionType: String?
    let logoUrl: String?
    let idTransaction: String
    let accountId: String
    let plaidTransactionId: String?
    let isActive: Bool
    let createdAt: String
    let updatedAt: String
}

extension Transaction {
    /// Creates a Transaction from persisted data using JSON encoding
    /// This avoids conflicts with the Codable synthesized init
    static func fromPersisted(_ data: PersistedTransactionData) -> Transaction {
        // Build a JSON dictionary and decode it
        var dict: [String: Any] = [
            "amount": data.amount,
            "currency": data.currency,
            "transaction_date": data.transactionDate,
            "name": data.name,
            "pending": data.pending,
            "id_transaction": data.idTransaction,
            "account_id": data.accountId,
            "is_active": data.isActive,
            "created_at": data.createdAt,
            "updated_at": data.updatedAt
        ]

        if let merchantName = data.merchantName {
            dict["merchant_name"] = merchantName
        }
        if let category = data.category {
            dict["category"] = category
        }
        if let paymentChannel = data.paymentChannel {
            dict["payment_channel"] = paymentChannel
        }
        if let transactionType = data.transactionType {
            dict["transaction_type"] = transactionType
        }
        if let logoUrl = data.logoUrl {
            dict["logo_url"] = logoUrl
        }
        if let plaidTransactionId = data.plaidTransactionId {
            dict["plaid_transaction_id"] = plaidTransactionId
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(Transaction.self, from: jsonData)
        } catch {
            // Fallback: return a minimal transaction if decoding fails
            fatalError("Failed to create Transaction from persisted data: \(error)")
        }
    }
}
