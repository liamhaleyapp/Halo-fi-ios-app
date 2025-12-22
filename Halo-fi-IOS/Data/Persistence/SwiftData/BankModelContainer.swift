//
//  BankModelContainer.swift
//  Halo-fi-IOS
//
//  Factory for creating SwiftData ModelContainer for bank data persistence.
//  Includes both transaction and account models.
//

import Foundation
import SwiftData

enum BankModelContainer {
    /// Creates the ModelContainer for bank data persistence
    /// - Parameter inMemory: If true, creates an in-memory only container (for testing/previews)
    /// - Returns: Configured ModelContainer
    static func create(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            // Transaction models
            PersistedTransaction.self,
            TransactionSyncState.self,
            // Account models
            PersistedAccount.self,
            AccountSyncState.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create BankModelContainer: \(error)")
        }
    }

    /// Creates an in-memory ModelContainer for testing and SwiftUI previews
    static func createForPreview() -> ModelContainer {
        create(inMemory: true)
    }
}
