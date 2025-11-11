//
//  Halo_fi_IOSApp.swift
//  Halo-fi-IOS
//
//  Created by Liam Haley on 8/14/25.
//

import SwiftUI
import RevenueCat
import PlaidLink

@main
struct Halo_fi_IOSApp: App {
  @State private var userManager = UserManager()
  @State private var subscriptionService = SubscriptionService()
  @State private var bankDataManager = BankDataManager()
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
  
  private var accessibilityDifferentiation: Bool {
    themeMode == "High-Contrast"
  }
  
  init() {
    Purchases.configure(withAPIKey: "appl_cztDsZUjXdUpTlHKrQCxvbRdFKn")
  }
  
  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(userManager)
        .environment(subscriptionService)
        .environment(bankDataManager)
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
          // Handles halofi://plaid-oauth?... from your Vercel page
          _ = Plaid.shared().handleRedirectURL(url)
        }
    }
  }
}
