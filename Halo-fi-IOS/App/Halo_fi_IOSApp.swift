//
//  Halo_fi_IOSApp.swift
//  Halo-fi-IOS
//
//  Created by Liam Haley on 8/14/25.
//

import SwiftUI
import SwiftData
import RevenueCat

@main
// swiftlint:disable:next type_name
struct Halo_fi_IOSApp: App {
  /// SwiftData ModelContainer for transaction persistence
  private let modelContainer: ModelContainer

  /// Central dependency injection container - owns all services
  @State private var container: DIContainer

  /// Services not yet in DIContainer (to be migrated)
  @State private var subscriptionService = SubscriptionService()
  @State private var plaidManager = PlaidManager()

  @AppStorage("themeMode") private var themeMode = "System"

  private var preferredColorScheme: ColorScheme? {
    switch themeMode {
    case "Light":
      return .light
    case "Dark":
      return .dark
    case "High-Contrast":
      return .dark
    case "System":
      return nil
    default:
      return nil
    }
  }

  init() {
    // Initialize SwiftData container for transaction persistence
    let modelContainer = TransactionModelContainer.create()
    self.modelContainer = modelContainer

    // Create persistence service and inject into DIContainer
    let transactionPersistence = TransactionPersistence(modelContainer: modelContainer)
    self._container = State(initialValue: DIContainer(transactionPersistence: transactionPersistence))

    // Configure RevenueCat
    Purchases.logLevel = .error
    Purchases.configure(withAPIKey: "appl_cztDsZUjXdUpTlHKrQCxvbRdFKn")
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .modelContainer(modelContainer)
        .environment(container)
        .environment(container.userManager)
        .environment(container.bankDataManager)
        .environment(container.permissionManager)
        .environment(subscriptionService)
        .environment(plaidManager)
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
          Task {
            if container.permissionManager.microphonePermission == .notDetermined {
              _ = await container.permissionManager.requestMicrophonePermission()
            }
            await subscriptionService.initialize()
          }
        }
        .onOpenURL { url in
          // Handles halofi://plaid-oauth?... redirect URLs from Plaid OAuth flow
          _ = plaidManager.handleRedirectURL(url)
        }
    }
  }
}
