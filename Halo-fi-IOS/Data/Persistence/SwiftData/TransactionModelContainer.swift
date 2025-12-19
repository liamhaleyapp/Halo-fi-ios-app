//
//  TransactionModelContainer.swift
//  Halo-fi-IOS
//
//  Factory for creating SwiftData ModelContainer for transaction persistence.
//

import Foundation
import SwiftData

enum TransactionModelContainer {
    /// Creates the ModelContainer for transaction persistence
    /// - Parameter inMemory: If true, creates an in-memory only container (for testing/previews)
    /// - Returns: Configured ModelContainer
    static func create(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            PersistedTransaction.self,
            TransactionSyncState.self
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create TransactionModelContainer: \(error)")
        }
    }

    /// Creates an in-memory ModelContainer for testing and SwiftUI previews
    static func createForPreview() -> ModelContainer {
        create(inMemory: true)
    }
}
