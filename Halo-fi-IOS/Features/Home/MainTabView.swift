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
    /// Posted by MainTabView when the user navigates away from the
    /// Accounts tab. AccountsOverviewView listens and clears its
    /// NavigationPath so the next visit lands on the institutions
    /// list instead of whichever nested view they were on.
    static let resetAccountsNavigation = Notification.Name("resetAccountsNavigation")
    /// Same idea for the Settings tab — leaving Settings while
    /// nested in Profile / Preferences / About / etc. should land
    /// the user back on the Settings root next time they re-enter.
    static let resetSettingsNavigation = Notification.Name("resetSettingsNavigation")
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
        case aiConsent
        case main
    }

    /// Bumped when the AI-consent gate resolves. `aiConsentGranted` reads
    /// UserDefaults (not observable state), so the route must take an
    /// explicit dependency to re-evaluate after consent is recorded.
    @State private var consentRefreshToken = 0

    private var currentRoute: AppRoute {
        _ = consentRefreshToken
        if !userManager.isAuthenticated {
            return .loggedOut
        } else if userManager.isResolvingDestination {
            return .resolving
        } else if !userManager.isOnboarded {
            return .onboarding
        } else if !userManager.aiConsentGranted {
            // Apple 5.1.1(i): consent must gate EVERY path into the app,
            // not just first-run onboarding. Users who skip onboarding
            // (existing accounts, reinstalls, pre-provisioned demo
            // accounts) land here until consent is recorded.
            return .aiConsent
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
                // Game-quality haptic: ascending tick keyed to tab
                // index so blind users feel which tab they landed on
                // by pitch alone. 4 tabs (0-3) → progress 0.0 / 0.33
                // / 0.67 / 1.0. Pairs with the existing earcon
                // sound for a multi-channel cue.
                let totalTabs = 4
                let progress = Double(newTab) / Double(max(totalTabs - 1, 1))
                Haptics.engine.play(.tickAscending(progress: progress))
            }
            // Leaving the Accounts tab resets its nested navigation
            // so the user always re-enters at the institutions list,
            // not whichever account/transaction detail they were
            // viewing previously.
            if oldTab == 1 && newTab != 1 {
                NotificationCenter.default.post(
                    name: .resetAccountsNavigation,
                    object: nil
                )
            }
            // Same treatment for the Settings tab — re-entering
            // should always land on the root list, not a nested
            // Profile / About / Preferences view.
            if oldTab == 3 && newTab != 3 {
                NotificationCenter.default.post(
                    name: .resetSettingsNavigation,
                    object: nil
                )
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
        case .aiConsent:
            AIConsentView(
                onAccept: { consentRefreshToken += 1 },
                // AIConsentView signs the user out on decline; the
                // isAuthenticated flip re-routes to loggedOut. The bump
                // just forces the route to re-evaluate immediately.
                onDecline: { consentRefreshToken += 1 }
            )
            .task {
                // Server is the source of truth. A consented user on a
                // fresh install may hit this gate before the async
                // hydration lands — re-check and self-dismiss rather
                // than re-prompting someone who already agreed.
                await userManager.refreshAIConsentFromServer()
                if userManager.aiConsentGranted {
                    consentRefreshToken += 1
                }
            }
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
