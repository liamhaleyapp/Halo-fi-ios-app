//
//  Halo_fi_IOSApp.swift
//  Halo-fi-IOS
//
//  Created by Liam Haley on 8/14/25.
//

import SwiftUI
import RevenueCat

@main
struct Halo_fi_IOSApp: App {
  @State private var userManager = UserManager()
  @State private var subscriptionService = SubscriptionService()
  @State private var bankDataManager = BankDataManager()
  @StateObject private var plaidManager = PlaidManager()
  @StateObject private var permissionManager = PermissionManager.shared
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
    Purchases.logLevel = .error
    Purchases.configure(withAPIKey: "appl_cztDsZUjXdUpTlHKrQCxvbRdFKn")
  }
  
  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(userManager)
        .environment(subscriptionService)
        .environment(bankDataManager)
        .environmentObject(plaidManager)
        .environmentObject(permissionManager)
        .preferredColorScheme(preferredColorScheme)
        .onAppear {
          Task {
            if permissionManager.microphonePermission == .notDetermined {
              _ = await permissionManager.requestMicrophonePermission()
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
