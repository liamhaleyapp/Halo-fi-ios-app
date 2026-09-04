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

/// WP4 tab order (Liam, 2026-09-03): Money · Benefits · Agent · Settings.
enum MainTab: Int {
    case money = 0, benefits = 1, agent = 2, settings = 3
}

struct MainTabView: View {
    @Environment(UserManager.self) private var userManager
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(BankDataManager.self) private var bankDataManager
    @Environment(BudgetDataManager.self) private var budgetDataManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = UITestArchetype.initialTabIndex ?? 0
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
        // WP4 UI-test seam: fixtures stand in for auth + network.
        if UITestArchetype.isActive {
            return .main
        }
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
            // WP4 tab order: 0 Money · 1 Benefits · 2 Agent · 3 Settings.
            // Leaving a tab resets its nested navigation so the user
            // always re-enters at that tab's root list.
            if oldTab == MainTab.money.rawValue && newTab != MainTab.money.rawValue {
                NotificationCenter.default.post(name: .resetMoneyNavigation, object: nil)
                NotificationCenter.default.post(name: .resetAccountsNavigation, object: nil)
            }
            if oldTab == MainTab.benefits.rawValue && newTab != MainTab.benefits.rawValue {
                NotificationCenter.default.post(name: .resetBenefitsNavigation, object: nil)
            }
            if oldTab == MainTab.settings.rawValue && newTab != MainTab.settings.rawValue {
                NotificationCenter.default.post(name: .resetSettingsNavigation, object: nil)
            }
        }
        // Phase 11 Track B — quick-action "Ask Halo" deep-link.
        // Remember which tab the request came from so the user lands
        // back there when the conversation dismisses.
        .onReceive(NotificationCenter.default.publisher(for: .askHaloRequested)) { _ in
            guard currentRoute == .main else { return }
            if selectedTab != MainTab.agent.rawValue {
                conversationOriginTab = selectedTab
            }
            selectedTab = MainTab.agent.rawValue
        }
        // WP3 — a receipt arrived from the share extension: land on the
        // Budget tab, which opens the log form with it attached.
        .onReceive(NotificationCenter.default.publisher(for: .receiptShared)) { _ in
            guard currentRoute == .main else { return }
            selectedTab = MainTab.benefits.rawValue
        }
        // WP5 — server said accounts changed: refresh the bank store now.
        .onReceive(NotificationCenter.default.publisher(for: .bankDataDidMutate)) { _ in
            Task { await bankDataManager.forceRefresh() }
        }
        // WP4 — "Mark as work expense" from the Money tab lands on Benefits.
        .onReceive(NotificationCenter.default.publisher(for: .workExpenseDraftRequested)) { _ in
            guard currentRoute == .main else { return }
            selectedTab = MainTab.benefits.rawValue
        }
        // WP6 — a tapped reminder notification lands on Benefits.
        .onReceive(NotificationCenter.default.publisher(for: .ssiReminderOpened)) { _ in
            guard currentRoute == .main else { return }
            selectedTab = MainTab.benefits.rawValue
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
            MoneyHomeView()
                .tabItem {
                    Label("Money", systemImage: "banknote.fill")
                        .accessibilityHint("Accounts, budget, and recent transactions")
                }
                .tag(MainTab.money.rawValue)

            BenefitsHomeView()
                .tabItem {
                    Label("Benefits", systemImage: "heart.text.square.fill")
                        .accessibilityHint("SSI resource monitor, work expenses, and education")
                }
                .tag(MainTab.benefits.rawValue)

            HomeView()
                .tabItem {
                    Label("Agent", systemImage: "mic.circle.fill")
                        .accessibilityHint("Talk to Halo")
                }
                .tag(MainTab.agent.rawValue)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                        .accessibilityHint("App settings and preferences")
                }
                .tag(MainTab.settings.rawValue)
        }
        .accentColor(.blue)
        // No swipe-between-tabs gesture: it fought horizontal scrolls and
        // VoiceOver swipes, and moved blind users to another tab by accident.
        // The tab bar (and the three-finger VoiceOver swipe) is the only way.
        // WP4 — Magic Tap anywhere: the Money header, resource status, and
        // the next due task, in one breath.
        .accessibilityAction(.magicTap) {
            UIAccessibility.post(notification: .announcement, argument: magicTapText())
        }
        .task {
            seedUITestFixturesIfNeeded()
        }
    }

    // MARK: - WP4 helpers

    private func magicTapText() -> String {
        let money = TabSummaries.money(
            MoneySnapshot.make(bank: bankDataManager, budget: budgetDataManager),
            capabilities: userManager.capabilities
        )
        let deductions = budgetDataManager.ssiManualDeductions
        let benefits: TabSummary? = userManager.capabilities.showsBenefitsLane
            ? TabSummaries.benefits(
                capabilities: userManager.capabilities,
                ssi: budgetDataManager.overview?.ssiStatus,
                expensesThisMonth: deductions.count,
                expensesTotalCents: deductions.reduce(0) { $0 + $1.amountCents },
                expensesImpactCents: deductions.reduce(0) { $0 + ($1.estimatedCheckImpactCents ?? 0) }
            )
            : nil
        var nextTask: String?
        let needsReceipt = deductions.filter { $0.resolvedMatchStatus == "needs_receipt" }.count
        if needsReceipt > 0 {
            nextTask = "Next: add a receipt to \(VoiceOverFormatter.count(needsReceipt, singular: "expense", plural: "expenses"))."
        } else if !budgetDataManager.ssiCandidates.isEmpty {
            nextTask = "Next: confirm \(VoiceOverFormatter.count(budgetDataManager.ssiCandidates.count, singular: "possible work expense", plural: "possible work expenses"))."
        } else if (bankDataManager.linkedItems ?? []).contains(where: { !$0.isActive }) {
            nextTask = "Next: reconnect a bank that needs attention."
        }
        return TabSummaries.magicTap(money: money, benefits: benefits, nextTask: nextTask)
    }

    private func seedUITestFixturesIfNeeded() {
        guard let archetype = UITestArchetype.current else { return }
        userManager.capabilities = archetype.capabilities
        bankDataManager.configureForUser(userId: "uitest")
        bankDataManager.setLinkedItems(archetype.linkedItems)
        bankDataManager.accountsByItemId = archetype.accountsByItemId
        budgetDataManager.overview = archetype.overview
    }

}

#Preview {
  MainTabView()
}
