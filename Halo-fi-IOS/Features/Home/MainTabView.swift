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
        // Check if user needs to complete onboarding
        // Use UserManager's isOnboarded property which persists independently
        if !userManager.isOnboarded {
          // User is authenticated but not onboarded - show unified onboarding flow
          UnifiedOnboardingFlowView()
        } else {
          // User is fully onboarded - show main app
          TabView {
            HomeView()
              .tabItem {
                Image(systemName: "mic.circle.fill")
                Text("Agent")
              }
              .tag(0)
            
            AccountsOverviewView()
              .tabItem {
                Image(systemName: "creditcard.fill")
                Text("Account")
              }
              .tag(1)
            
            SettingsView()
              .tabItem {
                Image(systemName: "gearshape.fill")
                Text("Settings")
              }
              .tag(2)
          }
          .accentColor(.blue)
        }
      } else {
        OnboardingView()
      }
    }
  }
}

#Preview {
  MainTabView()
}
