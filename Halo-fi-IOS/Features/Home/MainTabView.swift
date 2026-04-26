//
//  MainTab.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

extension Notification.Name {
    /// Phase 11 Track B — posted by quick-action buttons that want
    /// to deep-link to the Agent (voice) tab without injecting an
    /// environment binding all the way down the view tree.
    static let askHaloRequested = Notification.Name("askHaloRequested")
}

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
        // Phase 11 Track B — quick-action "Ask Halo" deep-link.
        .onReceive(NotificationCenter.default.publisher(for: .askHaloRequested)) { _ in
            if currentRoute == .main {
                selectedTab = 0
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

            BudgetView()
                .tabItem {
                    Label("Budget", systemImage: "chart.pie.fill")
                        .accessibilityHint("Monthly spending, income, and SSI status")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                        .accessibilityHint("App settings and preferences")
                }
                .tag(3)
        }
        .accentColor(.blue)
        // Horizontal swipe between tabs. simultaneousGesture so it
        // coexists with horizontal scroll views inside individual
        // tabs (the conversation transcript, settings rows, etc.).
        // VoiceOver intercepts touches before this fires, so blind
        // users keep using the tab bar buttons — no accessibility
        // regression. Swipe is a sighted-user convenience only.
        .simultaneousGesture(swipeBetweenTabs)
    }

    /// Drag threshold below which a swipe is treated as scrolling
    /// content rather than a tab switch. 50pt feels deliberate
    /// without being awkward.
    private var swipeBetweenTabs: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // Reject if the gesture was mostly vertical — that's
                // a scroll, not a tab swipe.
                guard abs(dx) > abs(dy) * 1.5 else { return }
                let threshold: CGFloat = 50
                if dx < -threshold && selectedTab < 3 {
                    withAnimation(.easeOut(duration: 0.25)) {
                        selectedTab += 1
                    }
                } else if dx > threshold && selectedTab > 0 {
                    withAnimation(.easeOut(duration: 0.25)) {
                        selectedTab -= 1
                    }
                }
            }
    }
}

#Preview {
  MainTabView()
}
