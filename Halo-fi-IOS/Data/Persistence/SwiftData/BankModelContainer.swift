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

        let persistentConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )

        // Try the requested config first.
        do {
            return try ModelContainer(for: schema, configurations: [persistentConfig])
        } catch {
            // SwiftData migration / store corruption shouldn't take down
            // the whole app — bank data is a cache; the server is source
            // of truth and re-syncs on launch.
            Logger.error("BankModelContainer: persistent init failed: \(error)")
        }

        // Step 1: try to recover by deleting the on-disk store and
        // letting SwiftData recreate from scratch. We only do this for
        // the persistent path; in-memory failure means SwiftData itself
        // is broken and there's nothing to delete.
        if !inMemory {
            do {
                try Self.wipePersistentStore()
                Logger.warning("BankModelContainer: wiped persistent store, retrying init")
                return try ModelContainer(for: schema, configurations: [persistentConfig])
            } catch {
                Logger.error("BankModelContainer: retry after wipe failed: \(error)")
            }
        }

        // Step 2: in-memory fallback. App is degraded (no offline cache,
        // no instant-display on launch) but functional.
        Logger.error("BankModelContainer: falling back to in-memory store")
        let inMemoryConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [inMemoryConfig])
        } catch {
            // If even in-memory fails, SwiftData is fundamentally broken
            // on this device. fatalError here is honest — there's no
            // graceful recovery, and silently returning a no-op container
            // would corrupt every read/write downstream.
            fatalError("BankModelContainer: in-memory fallback failed: \(error)")
        }
    }

    /// Best-effort delete of SwiftData's default-store directory so the
    /// next ModelContainer init can recreate it. Used as a recovery step
    /// when a migration error blocks normal init.
    private static func wipePersistentStore() throws {
        let fm = FileManager.default
        guard let appSupport = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        // SwiftData places its sqlite files in ~/Library/Application Support
        // by default. We don't know the exact filename across iOS versions,
        // so wipe anything that looks like a default store. Anything we
        // care about is in the server, not here.
        let candidates = ["default.store", "default.store-shm", "default.store-wal"]
        for name in candidates {
            let url = appSupport.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }
    }

    /// Creates an in-memory ModelContainer for testing and SwiftUI previews
    static func createForPreview() -> ModelContainer {
        create(inMemory: true)
    }
}
