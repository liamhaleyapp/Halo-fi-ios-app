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
    /// Posted by HomeView when the ConversationView dismisses. Used by
    /// MainTabView to restore the user to whichever tab they came from
    /// when the conversation was launched cross-tab via askHaloRequested.
    static let conversationDismissed = Notification.Name("conversationDismissed")
}

struct MainTabView: View {
    @Environment(UserManager.self) private var userManager
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(BankDataManager.self) private var bankDataManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var feedbackService = AudioFeedbackService()
    /// Tab the user was on when a cross-tab conversation was launched.
    /// Restored when the conversation dismisses so the user lands back
    /// where they started rather than getting stranded on the Agent tab.
    @State private var conversationOriginTab: Int? = nil

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
        // Remember which tab the request came from so the user lands
        // back there when the conversation dismisses.
        .onReceive(NotificationCenter.default.publisher(for: .askHaloRequested)) { _ in
            guard currentRoute == .main else { return }
            if selectedTab != 0 {
                conversationOriginTab = selectedTab
            }
            selectedTab = 0
        }
        // Posted by HomeView when ConversationView closes. Restore the
        // originating tab if we recorded one (otherwise stay on Agent
        // — the user opened the agent directly).
        .onReceive(NotificationCenter.default.publisher(for: .conversationDismissed)) { _ in
            if let origin = conversationOriginTab {
                selectedTab = origin
                conversationOriginTab = nil
            }
        }
        // Refresh bank data on foreground. Plaid webhooks update the
        // backend, but the iOS in-memory cache only reloads when a view
        // is rebuilt — so a user who left the app for an hour was seeing
        // stale balances on return. refreshIfStale's own threshold guard
        // prevents thrash if they background/foreground rapidly.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, currentRoute == .main else { return }
            Task { await bankDataManager.refreshIfStale() }
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
