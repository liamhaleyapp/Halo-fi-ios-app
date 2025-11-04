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
  @State private var showingSubscriptionOnboarding = false
  @State private var showingPlaidOnboarding = false
  
  var body: some View {
    Group {
      if userManager.isAuthenticated {
        // Check if user needs to complete onboarding
        if let user = userManager.currentUser, !user.isOnboarded {
          // User is authenticated but not onboarded - show onboarding flow
          OnboardingRedirectView(
            showingSubscriptionOnboarding: $showingSubscriptionOnboarding,
            showingPlaidOnboarding: $showingPlaidOnboarding
          )
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
          .preferredColorScheme(.dark)
        }
      } else {
        OnboardingView()
      }
    }
    .fullScreenCover(isPresented: $showingSubscriptionOnboarding) {
      SubscriptionOnboardingFlowView()
    }
    .fullScreenCover(isPresented: $showingPlaidOnboarding) {
      PlaidOnboardingView()
    }
  }
}

// Helper view to redirect to onboarding
struct OnboardingRedirectView: View {
  @Environment(SubscriptionService.self) private var subscriptionService
  @Binding var showingSubscriptionOnboarding: Bool
  @Binding var showingPlaidOnboarding: Bool
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      ProgressView()
        .tint(.white)
    }
    .task {
      await checkOnboardingStatus()
    }
  }
  
  private func checkOnboardingStatus() async {
    // Initialize subscription service to check status
    await subscriptionService.initialize()
    
    await MainActor.run {
      if subscriptionService.hasActiveSubscription {
        // Has subscription - go to Plaid
        showingPlaidOnboarding = true
      } else {
        // No subscription - go to subscription flow
        showingSubscriptionOnboarding = true
      }
    }
  }
}

#Preview {
  MainTabView()
}
