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
/// Tabs are addressed by identity, never by position: the Benefits tab is
/// absent for users whose answers say no SSI and no SSDI (2026-09-04).
enum MainTab: Int, CaseIterable, Identifiable {
    case money = 0, benefits = 1, agent = 2, settings = 3
    var id: Int { rawValue }

    static func visible(for capabilities: UserCapabilities) -> [MainTab] {
        allCases.filter { $0 != .benefits || capabilities.showsBenefitsTab }
    }
}

struct MainTabView: View {
    @Environment(UserManager.self) private var userManager
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(BankDataManager.self) private var bankDataManager
    @Environment(BudgetDataManager.self) private var budgetDataManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: MainTab = UITestArchetype.initialTab ?? .money
    @State private var feedbackService = AudioFeedbackService()
    /// Tab the user was on when a cross-tab conversation was launched.
    /// Restored when the conversation dismisses so the user lands back
    /// where they started rather than getting stranded on the Agent tab.
    @State private var conversationOriginTab: MainTab? = nil

    private var visibleTabs: [MainTab] { MainTab.visible(for: userManager.capabilities) }

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
                selectedTab = .money
            } else if !UITestArchetype.isActive {
                // The lane decides which tabs exist; make sure it is fresh
                // the moment the tabs appear.
                Task { await userManager.refreshCapabilitiesIfStale() }
            }
        }
        .onChange(of: visibleTabs) { oldTabs, newTabs in
            // The Benefits tab comes and goes with the questionnaire answers.
            if !newTabs.contains(selectedTab) {
                // The user is standing on a tab that just vanished (they
                // answered "no SSI, no SSDI" from the Benefits tab): land on
                // Money and say why, after the system's own screen-change
                // announcement has had its turn (BudgetView pattern).
                selectedTab = .money
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    UIAccessibility.post(
                        notification: .screenChanged,
                        argument: "No SSI or SSDI on file. The Benefits tab is hidden. You can set it up again in Settings, Benefits profile."
                    )
                }
            } else if !oldTabs.contains(.benefits), newTabs.contains(.benefits), currentRoute == .main {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    UIAccessibility.post(notification: .announcement, argument: "Benefits tab added.")
                }
            }
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            if oldTab != newTab {
                feedbackService.playTabSwitchFeedback()
                // Game-quality haptic: ascending tick keyed to the tab's
                // POSITION among the visible tabs so blind users feel which
                // tab they landed on by pitch alone (first 0.0 … last 1.0).
                // Pairs with the existing earcon for a multi-channel cue.
                let tabs = visibleTabs
                let position = tabs.firstIndex(of: newTab) ?? 0
                let progress = Double(position) / Double(max(tabs.count - 1, 1))
                Haptics.engine.play(.tickAscending(progress: progress))
            }
            // Leaving a tab resets its nested navigation so the user
            // always re-enters at that tab's root list.
            if oldTab == .money && newTab != .money {
                NotificationCenter.default.post(name: .resetMoneyNavigation, object: nil)
                NotificationCenter.default.post(name: .resetAccountsNavigation, object: nil)
            }
            if oldTab == .benefits && newTab != .benefits {
                NotificationCenter.default.post(name: .resetBenefitsNavigation, object: nil)
            }
            if oldTab == .settings && newTab != .settings {
                NotificationCenter.default.post(name: .resetSettingsNavigation, object: nil)
            }
        }
        // Phase 11 Track B — quick-action "Ask Halo" deep-link.
        // Remember which tab the request came from so the user lands
        // back there when the conversation dismisses.
        .onReceive(NotificationCenter.default.publisher(for: .askHaloRequested)) { _ in
            guard currentRoute == .main else { return }
            if selectedTab != .agent {
                conversationOriginTab = selectedTab
            }
            selectedTab = .agent
        }
        // WP3 — a receipt arrived from the share extension: land on the
        // Benefits tab, which opens the log form with it attached.
        .onReceive(NotificationCenter.default.publisher(for: .receiptShared)) { _ in
            guard currentRoute == .main else { return }
            openBenefitsTab()
        }
        // WP5 — server said accounts changed: refresh the bank store now.
        .onReceive(NotificationCenter.default.publisher(for: .bankDataDidMutate)) { _ in
            Task { await bankDataManager.forceRefresh() }
        }
        // WP4 — "Mark as work expense" from the Money tab lands on Benefits.
        .onReceive(NotificationCenter.default.publisher(for: .workExpenseDraftRequested)) { _ in
            guard currentRoute == .main else { return }
            openBenefitsTab()
        }
        // WP6 — a tapped reminder notification lands on Benefits.
        .onReceive(NotificationCenter.default.publisher(for: .ssiReminderOpened)) { _ in
            guard currentRoute == .main else { return }
            openBenefitsTab()
        }
        // Posted by HomeView when ConversationView closes. Restore the
        // originating tab if we recorded one and it still exists
        // (otherwise stay on Agent — the user opened the agent directly).
        .onReceive(NotificationCenter.default.publisher(for: .conversationDismissed)) { _ in
            if let origin = conversationOriginTab {
                selectedTab = visibleTabs.contains(origin) ? origin : .money
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
            if !UITestArchetype.isActive {
                Task { await userManager.refreshCapabilitiesIfStale() }
            }
        }
    }

    /// Deep links that end on the Benefits tab — a shared receipt, "mark as
    /// work expense", a reminder — only make sense when the tab exists.
    private func openBenefitsTab() {
        if visibleTabs.contains(.benefits) {
            selectedTab = .benefits
        } else {
            UIAccessibility.post(
                notification: .announcement,
                argument: "Receipts and work expenses need a benefits profile. Set it up in Settings."
            )
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
            ForEach(visibleTabs) { tab in
                tabRoot(tab)
                    .tabItem { tabLabel(tab) }
                    .tag(tab)
            }
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

    // MARK: - Tabs

    @ViewBuilder
    private func tabRoot(_ tab: MainTab) -> some View {
        switch tab {
        case .money: MoneyHomeView()
        case .benefits: BenefitsHomeView()
        case .agent: HomeView()
        case .settings: SettingsView()
        }
    }

    @ViewBuilder
    private func tabLabel(_ tab: MainTab) -> some View {
        switch tab {
        case .money:
            Label("Money", systemImage: "banknote.fill")
                .accessibilityHint("Accounts, budget, and recent transactions")
        case .benefits:
            Label("Benefits", systemImage: "heart.text.square.fill")
                .accessibilityHint("Work expenses, monthly package, and your benefits profile")
        case .agent:
            Label("Agent", systemImage: "mic.circle.fill")
                .accessibilityHint("Talk to Halo")
        case .settings:
            Label("Settings", systemImage: "gearshape.fill")
                .accessibilityHint("App settings and preferences")
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
                expensesImpactCents: deductions.reduce(0) { $0 + ($1.estimatedCheckImpactCents ?? 0) },
                reminders: budgetDataManager.ssiReminders,
                needsReceiptCount: deductions.filter { $0.resolvedMatchStatus == "needs_receipt" }.count
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
