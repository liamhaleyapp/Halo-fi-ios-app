//
//  Halo_fi_IOSApp.swift
//  Halo-fi-IOS
//
//  Created by Liam Haley on 8/14/25.
//

import SwiftUI
import SwiftData
import RevenueCat
import GoogleSignIn

@main
// swiftlint:disable:next type_name
struct Halo_fi_IOSApp: App {
  /// SwiftData ModelContainer for bank data persistence (transactions + accounts)
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
    // Initialize SwiftData container for bank data persistence
    let modelContainer = BankModelContainer.create()
    self.modelContainer = modelContainer

    // Create persistence services and inject into DIContainer
    let transactionPersistence = TransactionPersistence(modelContainer: modelContainer)
    let accountPersistence = AccountPersistence(modelContainer: modelContainer)
    self._container = State(initialValue: DIContainer(
        transactionPersistence: transactionPersistence,
        accountPersistence: accountPersistence
    ))

    // Configure RevenueCat
    Purchases.logLevel = .error
    Purchases.configure(withAPIKey: "appl_cztDsZUjXdUpTlHKrQCxvbRdFKn")

    // Configure Google Sign In
    GIDSignIn.sharedInstance.configuration = GIDConfiguration(
      clientID: "1006405353603-hiot2h2g6c73eruekv8tfqa3t1oj1596.apps.googleusercontent.com"
    )
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .buttonStyle(HapticButtonStyle())
        .modelContainer(modelContainer)
        .environment(container)
        .environment(container.userManager)
        .environment(container.bankDataManager)
        .environment(container.budgetDataManager)
        .environment(container.permissionManager)
        .environment(subscriptionService)
        .environment(plaidManager)
        .preferredColorScheme(preferredColorScheme)
        .privacyScreen()
        .onAppear {
          Task {
            await subscriptionService.initialize()
          }
        }
        .onOpenURL { url in
          // Handle Google Sign In callback
          if GIDSignIn.sharedInstance.handle(url) { return }
          // Handles halofi://plaid-oauth?... redirect URLs from Plaid OAuth flow
          _ = plaidManager.handleRedirectURL(url)
        }
    }
  }
}

/// Covers the whole app with an opaque screen whenever it isn't active, so the
/// iOS App Switcher snapshot can't leak balances or transactions to anyone who
/// opens the multitasker (F048). Uses `scenePhase != .active`, which triggers
/// during the pre-snapshot `.inactive` phase.
private struct PrivacyScreenModifier: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase
  // Scales with Dynamic Type (App Store Guideline 4).
  @ScaledMetric(relativeTo: .largeTitle) private var lockIconSize: CGFloat = 44

  func body(content: Content) -> some View {
    content.overlay {
      if scenePhase != .active {
        ZStack {
          Color(.systemBackground).ignoresSafeArea()
          Image(systemName: "lock.fill")
            .font(.system(size: lockIconSize))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
      }
    }
  }
}

private extension View {
  func privacyScreen() -> some View { modifier(PrivacyScreenModifier()) }
}
