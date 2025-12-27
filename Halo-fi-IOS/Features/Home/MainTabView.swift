//
//  MainTab.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct MainTabView: View {
  @Environment(UserManager.self) private var userManager
  @Environment(SubscriptionService.self) private var subscriptionService
  @State private var selectedTab = 0

  var body: some View {
    Group {
      if userManager.isAuthenticated {
        if userManager.isResolvingDestination {
          // Show splash while determining destination (fetching account data)
          PostLoginSplashView()
        } else if !userManager.isOnboarded {
          // User is authenticated but not onboarded - show unified onboarding flow
          UnifiedOnboardingFlowView()
            .dynamicTypeSize(.medium ... .accessibility5)
        } else {
          // User is fully onboarded - show main app
          TabView(selection: $selectedTab) {
            HomeView()
              .tabItem {
                Label("Agent", systemImage: "mic.circle.fill")
                  .accessibilityHint("Voice assistant and home screen")
              }
              .tag(0)

            AccountsOverviewView()
              .tabItem {
                Label("Account", systemImage: "creditcard.fill")
                  .accessibilityHint("View and manage your financial accounts")
              }
              .tag(1)

            SettingsView()
              .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
                  .accessibilityHint("App settings and preferences")
              }
              .tag(2)
          }
          .accentColor(.blue)
        }
      } else {
        OnboardingView()
      }
    }
    .onChange(of: userManager.isResolvingDestination) { _, isResolving in
      // Reset to home tab when destination is resolved (after login)
      if !isResolving {
        selectedTab = 0
      }
    }
  }
}

#Preview {
  MainTabView()
}
