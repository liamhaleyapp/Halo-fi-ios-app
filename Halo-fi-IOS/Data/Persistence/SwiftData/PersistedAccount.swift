//
//  PersistedAccount.swift
//  Halo-fi-IOS
//
//  SwiftData model for persisting bank accounts locally.
//  Uses Codable payload storage for simplicity and future-proofing.
//

import Foundation
import SwiftData

@Model
final class PersistedAccount {
    // MARK: - Primary Key

    /// Composite key for upsert without duplicates: {userId}_{plaidItemId}_{accountId}
    @Attribute(.unique) var compositeId: String

    // MARK: - Query Keys (for efficient filtering)

    /// User isolation - ensures accounts don't leak between users
    var userId: String

    /// Plaid item this account belongs to
    var plaidItemId: String

    /// Account ID for matching during save/update
    var accountId: String

    // MARK: - Payload (JSON-encoded BankAccount)

    /// The full BankAccount stored as JSON Data
    var payloadData: Data

    // MARK: - Metadata

    /// When this record was last synced from the server
    var lastSyncedAt: Date

    // MARK: - Initialization

    init(from account: BankAccount, userId: String, plaidItemId: String) {
        self.userId = userId
        self.plaidItemId = plaidItemId
        self.accountId = account.idAccount
        self.compositeId = "\(userId)_\(plaidItemId)_\(account.idAccount)"
        self.lastSyncedAt = Date()

        // Encode the full BankAccount as JSON
        do {
            self.payloadData = try JSONEncoder().encode(account)
        } catch {
            Logger.error("PersistedAccount: Failed to encode account: \(error)")
            self.payloadData = Data()
        }
    }

    // MARK: - Update

    /// Updates this persisted account with new data from the server
    func update(from account: BankAccount) {
        self.lastSyncedAt = Date()

        do {
            self.payloadData = try JSONEncoder().encode(account)
        } catch {
            Logger.error("PersistedAccount: Failed to encode account during update: \(error)")
        }
    }

    // MARK: - Conversion

    /// Converts this persisted account back to a BankAccount struct
    func toBankAccount() -> BankAccount? {
        do {
            return try JSONDecoder().decode(BankAccount.self, from: payloadData)
        } catch {
            Logger.error("PersistedAccount: Failed to decode account: \(error)")
            return nil
        }
    }
}
