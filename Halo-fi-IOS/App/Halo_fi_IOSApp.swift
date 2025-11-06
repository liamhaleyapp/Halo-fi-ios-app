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
  @StateObject private var permissionManager = PermissionManager.shared
  
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
        .onAppear {
          // Request microphone permission early for accessibility
          Task {
            if permissionManager.microphonePermission == .notDetermined {
              _ = await permissionManager.requestMicrophonePermission()
            }
          }
          
          // Initialize subscription service
          Task {
            await subscriptionService.initialize()
          }
        }
    }
  }
}
