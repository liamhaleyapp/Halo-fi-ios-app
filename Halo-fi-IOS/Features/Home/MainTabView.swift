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
    @State private var feedbackService = AudioFeedbackService()

    private enum AppRoute: Equatable {
        case loggedOut
        case resolving
        case onboarding
        case main
    }

    private var currentRoute: AppRoute {
        if !userManager.isAuthenticated {
            return .loggedOut
        } else if userManager.isResolvingDestination {
            return .resolving
        } else if !userManager.isOnboarded {
            return .onboarding
        } else {
            return .main
        }
    }

    var body: some View {
        ZStack {
            routeView
                .id(currentRoute)
        }
        .animation(.easeInOut(duration: 0.3), value: currentRoute)
        .onChange(of: currentRoute) { _, newRoute in
            if newRoute != .main {
                selectedTab = 0
            }
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            if oldTab != newTab {
                feedbackService.playTabSwitchFeedback()
            }
        }
    }

    @ViewBuilder
    private var routeView: some View {
        switch currentRoute {
        case .loggedOut:
            OnboardingView()
                .viewTransition(.fade)
        case .resolving:
            PostLoginSplashView()
                .viewTransition(.fade)
        case .onboarding:
            UnifiedOnboardingFlowView()
                .dynamicTypeSize(.medium ... .accessibility5)
                .viewTransition(.fade)
        case .main:
            ZStack { tabContent }
                .viewTransition(.fade)
        }
    }

    private var tabContent: some View {
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
        .highPriorityGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    let horizontal = value.translation.width
                    if horizontal < -50 && selectedTab < 2 {
                        selectedTab += 1
                    } else if horizontal > 50 && selectedTab > 0 {
                        selectedTab -= 1
                    }
                }
        )
    }
}

#Preview {
  MainTabView()
}
