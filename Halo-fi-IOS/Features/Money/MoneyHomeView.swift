//
//  MoneyHomeView.swift
//  Halo-fi-IOS
//
//  The Money tab (WP4, trimmed after Liam's first look): five VoiceOver
//  stops, top to bottom, no long lists on the tab itself:
//    a. Summary header — "Balance" verdict in words, then numbers
//    b. Budget row → BudgetView
//    c. Accounts row → AccountsListView (institutions → accounts → detail)
//    d. Recent transactions row → AllTransactionsView (every account, newest
//       first; rotor "Mark as work expense")
//    e. Link another account
//  For SSI profiles, investments are listed inside counted resources with
//  everything else — net worth is not the headline.
//

import SwiftUI

extension Notification.Name {
    /// Posted by the Money tab when a transaction is marked as a work
    /// expense; the Benefits tab opens the log form prefilled.
    static let workExpenseDraftRequested = Notification.Name("WorkExpenseDraftRequested")
    /// Posted by MainTabView when the user leaves the Money tab.
    static let resetMoneyNavigation = Notification.Name("ResetMoneyNavigation")
    /// Posted by MainTabView when the user leaves the Benefits tab.
    static let resetBenefitsNavigation = Notification.Name("ResetBenefitsNavigation")
}

/// A transaction the user wants logged as a work expense.
struct WorkExpenseDraft: Equatable {
    let amountCents: Int
    let description: String
    let occurredOn: Date
}

@MainActor
@Observable
final class WorkExpenseHandoff {
    static let shared = WorkExpenseHandoff()
    private(set) var pending: WorkExpenseDraft?

    func offer(_ draft: WorkExpenseDraft) {
        pending = draft
        NotificationCenter.default.post(name: .workExpenseDraftRequested, object: nil)
    }

    func take() -> WorkExpenseDraft? {
        defer { pending = nil }
        return pending
    }
}

struct MoneyHomeView: View {
    @Environment(BankDataManager.self) private var bankDataManager
    @Environment(BudgetDataManager.self) private var budgetDataManager
    @Environment(UserManager.self) private var userManager

    @State private var navigationPath = NavigationPath()
    @State private var showingLinkChooser = false
    @State private var showingMoneyProfile = false
    @State private var hasAppeared = false
    @State private var isLoadingTransactions = false
    /// View-owned copy of the all-accounts list, so cache resets elsewhere
    /// never blank the row once it has loaded.
    @State private var recentTransactions: [Transaction] = []
    /// Attention learn cards resolve in sheets.
    @State private var labelCard: AttentionCard?
    @State private var candidateCard: AttentionCard?
    @State private var billCard: AttentionCard?
    @State private var suggestionCard: AttentionCard?

    private static let transactionPageSize = 200

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.haloBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        TabTitle("Money")
                        header
                        AccountIdentityReviewSection()
                        attentionRow
                        budgetRow
                        incomeRow
                        if bankDataManager.hasInvestmentAccounts { investmentsRow }
                        billsRow
                        calendarRow
                        accountsRow
                        transactionsRow
                        linkSection
                        if UITestArchetype.isActive && ProcessInfo.processInfo.arguments.contains("--ui-test-money-changing-rows") {
                            Button("Simulate reconnect and refresh") {
                                budgetDataManager.attentionCards = []
                                budgetDataManager.attentionQueue = []
                                bankDataManager.accountsByItemId = [:]
                            }.accessibilityIdentifier("simulateMoneyRefresh")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                    .readableContentWidth()
                }
                .refreshable {
                    await bankDataManager.forceRefresh()
                    await budgetDataManager.refresh()
                    await loadTransactions(forceRefresh: true)
                    UIAccessibility.post(notification: .announcement, argument: "Updated. \(summary.verdict). \(summary.subline ?? "")")
                }
            }
            .task {
                // Foreground, after the first paint: the one place the
                // notification permission is asked.
                guard !UITestArchetype.isActive else { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await PushRegistrar.shared.requestPermissionIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .attentionOpened)) { _ in
                openAttentionFromNotification()
            }
            .onReceive(NotificationCenter.default.publisher(for: VoiceNavigation.budgetRequested)) { _ in
                if VoiceNavigation.consumeBudget() { navigationPath.append(MoneyRoute.budget) }
            }
            .onAppear {
                if VoiceNavigation.consumeBudget() { navigationPath.append(MoneyRoute.budget) }

                if ReminderNotificationScheduler.pendingAttentionOpen { openAttentionFromNotification() }
            }
            .navigationTitle("Money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingLinkChooser) { LinkAccountChooserView() }
            .fullScreenCover(isPresented: $showingMoneyProfile) { MoneyProfileSheet() }
            .onReceive(NotificationCenter.default.publisher(for: .accountLinked)) { _ in
                // First account in: offer the four money questions once,
                // after the link sheet has gone (Liam, 2026-09-05).
                guard MoneyProfilePrompt.shouldOfferAfterLink(remaining: userManager.capabilities.moneyProfileRemaining) else { return }
                MoneyProfilePrompt.markOffered()
                showingLinkChooser = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showingMoneyProfile = true }
            }
            .navigationDestination(for: ConnectedItem.self) { item in
                InstitutionAccountsView(item: item)
            }
            .navigationDestination(for: MoneyRoute.self) { route in
                switch route {
                case .reconnectBank(let itemId, let name): BankReconnectView(itemId: itemId, name: name)
                case .budget: BudgetView()
                case .attention: AttentionView(onOpen: { open($0) })
                case .accounts: AccountsListView(onLink: { showingLinkChooser = true })
                case .allTransactions: AllTransactionsView(initial: recentTransactions)
                case .resourceMonitor: ResourceMonitorView()
                case .income: IncomeView()
                case .investments: InvestmentsView()
                case .bills: BillsView()
                case .calendar: CalendarView()
                case .workExpenses: WorkExpensesView()
                case .package(let month): MonthlyPackageView(initialMonth: month)
                case .review(let month): MonthEndReviewView(month: month)
                }
            }
            // Benefits screens pushed from an attention card link onward
            // with their own routes; resolve them here too.
            .navigationDestination(for: BenefitsHomeView.Route.self) { route in
                switch route {
                case .resourceMonitor: ResourceMonitorView()
                case .workExpenses: WorkExpensesView()
                case .monthlyPackage(let month): MonthlyPackageView(initialMonth: month)
                case .monthEndReview(let month): MonthEndReviewView(month: month)
                case .learn: LearnListView(lane: userManager.capabilities.lane)
                case .benefitsProfile: BenefitsProfileView()
                case .questionnaire:
                    BenefitsQuestionnaireView(onFinished: {
                        if !navigationPath.isEmpty { navigationPath.removeLast(navigationPath.count) }
                    })
                }
            }
            .sheet(item: $labelCard) { card in
                DepositLabelSheet(card: card)
            }
            .sheet(item: $billCard) { card in
                BillConfirmSheet(card: card)
            }
            .sheet(item: $suggestionCard) { card in
                BudgetSuggestionSheet(card: card)
            }
            .sheet(item: $candidateCard) { card in
                if let candidate = card.candidate {
                    SSIDeductionConfirmView(candidate: candidate) { type in
                        budgetDataManager.resolveCard(card, refresh: false)
                        try await budgetDataManager.confirmSSIDeduction(candidate: candidate, as: type)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetMoneyNavigation)) { _ in
                if !navigationPath.isEmpty { navigationPath.removeLast(navigationPath.count) }
            }
            .task {
                guard !hasAppeared else { return }
                hasAppeared = true
                // These reads share authentication, but do not depend on another tab's data.
                async let banks: Void = bankDataManager.refreshIfStale()
                async let budget: Void = refreshBudgetIfNeeded()
                async let transactions: Void = loadTransactions(forceRefresh: false)
                _ = await (banks, budget, transactions)
            }
        }
    }

    private func refreshBudgetIfNeeded() async {
        if budgetDataManager.shouldRefresh { await budgetDataManager.refresh() }
    }

    enum MoneyRoute: Hashable {
        case budget, attention, accounts, allTransactions, resourceMonitor, income, bills, calendar, workExpenses, investments
        case reconnectBank(String, String)
        case package(String?)
        case review(String)
    }

    // MARK: - Attention actions

    /// A tapped notification: land on Needs your attention. The tab switch
    /// posts a navigation reset in the same frame, so the push waits a beat.
    private func openAttentionFromNotification() {
        ReminderNotificationScheduler.pendingAttentionOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if !navigationPath.isEmpty { navigationPath.removeLast(navigationPath.count) }
            navigationPath.append(MoneyRoute.attention)
        }
    }

    private func open(_ card: AttentionCard) {
        switch card.actionType {
        case "label_deposit", "enter_gross":
            if card.payload.transactionId != nil || card.payload.labelId != nil { labelCard = card }
        case "confirm_bill":
            if card.payload.streamId != nil { billCard = card }
        case "apply_budget_suggestion": suggestionCard = card
        case "open_budget": navigationPath.append(MoneyRoute.budget)
        case "open_benefits_profile": navigationPath.append(BenefitsHomeView.Route.benefitsProfile)
        case "confirm_candidate":
            if card.candidate != nil { candidateCard = card }
        case "open_resource_monitor": navigationPath.append(MoneyRoute.resourceMonitor)
        case "open_package": navigationPath.append(MoneyRoute.package(card.payload.month))
        case "open_review": navigationPath.append(MoneyRoute.review(card.payload.month ?? MonthKey.current))
        case "open_work_expenses": navigationPath.append(MoneyRoute.workExpenses)
        case "open_accounts":
            if card.kind == "bank_reconnect", let itemId = card.payload.itemId {
                let name = card.title.replacingOccurrences(of: "Reconnect ", with: "", options: .anchored)
                navigationPath.append(MoneyRoute.reconnectBank(itemId, name))
            } else { navigationPath.append(MoneyRoute.accounts) }
        case "open_link_bank": showingLinkChooser = true
        case "open_money_profile": showingMoneyProfile = true
        default: break
        }
    }


    // MARK: - a. Header

    var snapshot: MoneySnapshot {
        MoneySnapshot.make(bank: bankDataManager, budget: budgetDataManager)
    }

    private var summary: TabSummary {
        TabSummaries.money(snapshot, capabilities: userManager.capabilities)
    }

    @ViewBuilder
    private var header: some View {
        let showsResources = userManager.capabilities.showsResourceCounter
        let card = BalanceHeroCard(summary: summary, snapshot: snapshot, showsResources: showsResources)
        if showsResources, snapshot.resources != nil {
            // For SSI users the balance card is the resource counter and
            // opens the monitor (counted vs excluded accounts, actions).
            NavigationLink(value: MoneyRoute.resourceMonitor) { card }
                .buttonStyle(HapticPlainButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(summary.spoken)
                .accessibilityHint("Opens the resource monitor.")
                .accessibilityAddTraits([.isHeader, .isButton])
                .accessibilitySortPriority(1000)
                .accessibilityIdentifier(ScreenReaderSummaryHeader.accessibilityID)
        } else {
            card
        }
    }

    // MARK: - a2. Needs your attention (one row; the cards live on their own
    // screen — Liam, 2026-09-05: the main screens stay concise)

    private var attentionRow: some View {
        let sections = AttentionSections(cards: budgetDataManager.attentionCards + budgetDataManager.attentionQueue)
        let cards = sections.alerts
        let total = cards.count
        let top = cards.first
        // Always red when something is waiting (Liam, 2026-09-05): the row
        // has to stand apart from the tone-colored balance card above it.
        let tint: Color = top == nil ? .gray : .haloNegative
        let line: String = {
            guard let top else { return !sections.groups.isEmpty ? "No urgent alerts. Review questions available." : (budgetDataManager.isLoading ? "Checking…" : "Nothing right now.") }
            if total == 1 { return top.title + "." }
            return "\(VoiceOverFormatter.count(total, singular: "thing", plural: "things")). First: \(top.title)."
        }()
        return row(title: "Needs your attention", icon: "bell.badge.fill", tint: tint, line: line,
                   hint: total == 0 ? "Opens the list. It is empty right now." : "Opens the list, most urgent first.",
                   route: .attention)
    }

    // MARK: - b. Budget row

    private var budgetRow: some View {
        // Before the overview lands the row must not claim "No budget yet".
        let line = budgetDataManager.overview == nil ? "Loading…" : TabSummaries.budgetRow(snapshot)
        return row(title: "Budget", icon: "chart.pie.fill", tint: .blue, line: line,
                   hint: "Opens your budget.", route: .budget)
    }

    // MARK: - b2. Income row (2026-09-05)

    private var incomeRow: some View {
        let s = budgetDataManager.incomeSummary
        let line: String = {
            guard let s else { return "What your deposits are, learned as they arrive." }
            if let first = s.sources.first(where: { $0.kind == "work_income" }) {
                var text = first.employer ?? first.sourceKey.capitalized
                if let cadence = first.cadenceDays {
                    text += cadence == 14 ? " every 2 weeks" : cadence == 7 ? " every week" : cadence >= 28 ? " monthly" : cadence == 15 ? " twice a month" : ""
                }
                text += "."
                if s.paychecksNeedingGross > 0 { text += " \(VoiceOverFormatter.count(s.paychecksNeedingGross, singular: "paystub gross", plural: "paystub grosses")) needed." }
                return text
            }
            if !s.sources.isEmpty { return "\(VoiceOverFormatter.count(s.sources.count, singular: "payer", plural: "payers")) learned. No work income labeled yet." }
            return "What your deposits are, learned as they arrive."
        }()
        return row(title: "Income", icon: "arrow.down.circle.fill", tint: .indigo, line: line,
                   hint: "Opens your income: payers and this month's work income.", route: .income)
    }

    private var investmentsRow: some View {
        row(title: "Investments", icon: "chart.line.uptrend.xyaxis", tint: .purple,
            line: snapshot.investmentsCents.map { InvestmentSummary.money($0, currency: "USD") } ?? "Balance unavailable",
            hint: "Opens your linked investment accounts and holdings.", route: .investments)
    }

    // MARK: - b3. Bills row (2026-09-05)

    private var billsRow: some View {
        let b = budgetDataManager.bills
        let confirmed = b?.streams.filter { $0.userConfirmed == true } ?? []
        let unanswered = b?.streams.filter { $0.userConfirmed == nil }.count ?? 0
        let line: String = {
            guard let b else { return "Recurring charges Plaid sees, with your yes or no." }
            if confirmed.isEmpty {
                return unanswered > 0 ? "\(VoiceOverFormatter.count(unanswered, singular: "charge", plural: "charges")) waiting for a yes or no." : "No recurring charges spotted yet."
            }
            let subs = confirmed.filter { $0.isSubscription }.count
            let billsOnly = confirmed.count - subs
            var text = subs == 0
                ? "\(VoiceOverFormatter.count(billsOnly, singular: "bill", plural: "bills")), about \(VoiceOverFormatter.dollars(b.monthlyBillsCents)) a month."
                : "\(VoiceOverFormatter.count(billsOnly, singular: "bill", plural: "bills")) and \(VoiceOverFormatter.count(subs, singular: "subscription", plural: "subscriptions")), about \(VoiceOverFormatter.dollars(b.monthlyBillsCents)) a month."
            if unanswered > 0 { text += " \(unanswered) to answer." }
            return text
        }()
        return row(title: "Bills and subscriptions", icon: "calendar.badge.clock", tint: .teal, line: line,
                   hint: "Opens your recurring charges to answer which are bills or subscriptions.", route: .bills)
    }

    // MARK: - b4. Calendar row (2026-09-05)

    private var calendarRow: some View {
        let cal = budgetDataManager.calendar(for: nil)
        let line: String = {
            guard let cal else { return "The month ahead, from what you confirmed." }
            if let n = cal.next, let d = n.date {
                let amount = n.cents > 0 ? ", \(VoiceOverFormatter.dollars(n.cents))" : ""
                return "Next: \(n.label)\(amount), \(TabSummaries.spokenDate(d))."
            }
            return "Nothing confirmed for \(cal.monthLabel.split(separator: " ").first.map(String.init) ?? "this month") yet."
        }()
        return row(title: "Calendar", icon: "calendar", tint: .pink, line: line,
                   hint: "Opens the month day by day: income, bills, subscriptions and deadlines you confirmed.", route: .calendar)
    }

    // MARK: - c. Accounts row

    private var accountsRow: some View {
        let items = bankDataManager.linkedItems ?? []
        let manual = bankDataManager.manualAccounts.count
        let attention = items.filter { !$0.isActive }.count
        var line: String
        if items.isEmpty && manual == 0 {
            line = "No accounts yet. Link one below."
        } else {
            let groups = bankDataManager.institutionGroups
            let names = groups.map(\.name)
            let accountCount = groups.reduce(manual) { $0 + bankDataManager.accounts(in: $1).count }
            line = VoiceOverFormatter.count(accountCount, singular: "account", plural: "accounts")
            if !names.isEmpty { line += " at " + names.prefix(2).joined(separator: " and ") + (names.count > 2 ? " and more" : "") }
            line += "."
            if attention > 0 { line += " \(VoiceOverFormatter.count(attention, singular: "connection needs", plural: "connections need")) attention." }
        }
        return row(title: "Accounts", icon: "building.columns.fill", tint: .green, line: line,
                   hint: "Opens each institution, then each account and its transactions.", route: .accounts)
    }

    // MARK: - d. Recent transactions row

    private var transactionsRow: some View {
        let line: String
        if let newest = recentTransactions.first {
            line = "Newest: \(newest.displayName), \(Self.spokenDate(newest.transactionDate))."
        } else {
            line = isLoadingTransactions ? "Loading." : "Nothing yet. Pull down to refresh."
        }
        return row(title: "Recent transactions", icon: "list.bullet.rectangle.fill", tint: .orange, line: line,
                   hint: "Opens every transaction across your accounts, newest first.", route: .allTransactions)
    }

    private func loadTransactions(forceRefresh: Bool) async {
        isLoadingTransactions = true
        defer { isLoadingTransactions = false }
        let loaded = await bankDataManager.allTransactions(forceRefresh: forceRefresh, limit: Self.transactionPageSize)
        if !loaded.isEmpty || recentTransactions.isEmpty { recentTransactions = loaded }
    }

    // MARK: - e. Link

    private var linkSection: some View {
        Button { showingLinkChooser = true } label: {
            Label("Link another account", systemImage: "plus.circle.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Connect a bank with Plaid or add an account by hand.")
        .padding(.top, 8)
    }

    // MARK: - Row builder

    private func row(title: String, icon: String, tint: Color, line: String, hint: String, route: MoneyRoute) -> some View {
        NavigationLink(value: route) {
            HaloRow {
                HaloIconTile(icon: icon, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.haloRowTitle).foregroundColor(.haloTextPrimary)
                    Text(line).font(.subheadline).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HaloChevron()
            }
            .padding(16)
            .frame(minHeight: 72)
            .haloCard(tint: route == .attention && tint != .gray ? tint : nil)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
        }
        .buttonStyle(HapticPlainButtonStyle())
        .id(route)
        .contentShape(Rectangle())
        .accessibilityIdentifier("moneyRow-\(title)")
        .accessibilityLabel("\(title). \(line)")
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
    }

    static func spokenDate(_ iso: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMMM d"
        return out.string(from: d)
    }
}

// MARK: - Mark as work expense (shared by both transaction lists)

extension WorkExpenseHandoff {
    /// Hands the transaction to the Benefits tab with its REAL date (the
    /// old "See all" list used today's date, which put charges in the
    /// wrong month's package).
    func offer(transaction txn: Transaction) {
        let cents = Int((abs(txn.amount) * 100).rounded())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: String(txn.transactionDate.prefix(10))) ?? Date()
        Haptics.engine.play(.tapLight)
        offer(WorkExpenseDraft(amountCents: cents, description: txn.displayName, occurredOn: date))
    }
}

// MARK: - Snapshot from managers

extension MoneySnapshot {
    @MainActor static var lastReportedCash: Int = -1

    @MainActor
    static func make(bank: BankDataManager, budget: BudgetDataManager) -> MoneySnapshot {
        var cash = 0.0
        var owed = 0.0
        var investments = 0.0
        var investmentCount = 0
        var investmentBalancesKnown = true
        var count = 0
        // Single source: the per-institution accounts (what the Accounts page
        // lists). The flat /bank/accounts list is only a stopgap before the
        // first per-item load completes.
        // Linked, active connections only (2026-09-05): an item missing from
        // the per-item map is filled from the flat list rather than dropped,
        // so the headline never loses a bank because one feed lagged.
        var source: [BankAccount] = []
        var branch = ""
        if let linked = bank.linkedItems, !linked.isEmpty {
            for item in linked where item.isActive {
                if let list = bank.accountsByItemId[item.itemId], !list.isEmpty {
                    source += list
                    branch += "m\(list.count)"
                } else {
                    let fb = (bank.accounts ?? []).filter { $0.plaidItemId == item.plaidItemId || $0.plaidItemId == item.itemId }
                    source += fb
                    branch += "f\(fb.count)"
                }
            }
            branch += (linked.contains { !$0.isActive }) ? "+inactive" : ""
        } else {
            let perItem = bank.accountsByItemId.values.flatMap { $0 }
            source = perItem.isEmpty ? (bank.accounts ?? []) : perItem
            branch = bank.linkedItems == nil ? "nil-linked" : "empty-linked"
        }
        // Dedupe by account id: three feeds write accountsByItemId and a
        // stale or doubled entry must never change the headline number.
        var seenIds = Set<String>()
        var staleCount = 0
        var earliestStale: String?
        for account in source where account.isActive && seenIds.insert(account.idAccount).inserted {
            if let since = account.staleSince {
                staleCount += 1
                if earliestStale == nil || since < earliestStale! { earliestStale = since }
            }
            let balance = account.currentBalance ?? 0
            if account.type.lowercased() == "credit" || account.type.lowercased() == "loan" {
                owed += max(0, balance)
            } else if ["investment", "brokerage"].contains(account.type.lowercased()) {
                investments += balance
                investmentCount += 1
                if account.currentBalance == nil || account.currency != "USD" { investmentBalancesKnown = false }
            } else {
                count += 1
                cash += max(0, balance)
            }
        }
        for manual in bank.manualAccounts {
            let kind = String(describing: manual.accountType).lowercased()
            if kind.contains("credit") || kind.contains("loan") {
                owed += max(0, manual.balance)
            } else if kind.contains("investment") || kind.contains("brokerage") {
                investments += manual.balance
                investmentCount += 1
                if manual.currency != "USD" { investmentBalancesKnown = false }
            } else {
                count += 1
                cash += max(0, manual.balance)
            }
        }
        let attention = (bank.linkedItems ?? []).filter { !$0.isActive }.count
        // Breadcrumb when the headline changes (2026-09-06): which branch
        // built it, from how many accounts, with how many linked items.
        let cashInt = Int(cash.rounded())
        if cashInt != Self.lastReportedCash {
            Self.lastReportedCash = cashInt
            Diagnostics.send("hero_cash", ["cash": "\(cashInt)", "count": "\(count)", "branch": branch,
                                           "linked": "\((bank.linkedItems ?? []).count)", "map_items": "\(bank.accountsByItemId.count)",
                                           "flat": "\((bank.accounts ?? []).count)", "manual": "\(bank.manualAccounts.count)",
                                           "inactive_accts": "\(source.filter { !$0.isActive }.count)"])
        }
        let overview = budget.overview
        var daysLeft: Int?
        if let end = overview?.period.endUtc, let endDate = ISO8601DateFormatter().date(from: end) ?? isoNoFraction(end) {
            daysLeft = max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
        }
        let over = overview?.budgetStatus.categories.first(where: { $0.status == "over" })
            .map { BudgetFormatter.displayName(forCategory: $0.category) }
        return MoneySnapshot(
            cashCents: bank.balanceSummary?.cashCents ?? Int((cash * 100).rounded()),
            owedCents: bank.balanceSummary?.owedCents ?? Int((owed * 100).rounded()),
            accountCount: bank.balanceSummary?.accounts.filter { $0.kind == "cash" }.count ?? count,
            connectionsNeedingAttention: attention,
            resources: overview?.ssiStatus.resources,
            budgetTotal: overview?.budgetStatus.hasBudget == true ? overview?.budgetStatus.total : nil,
            spentCents: overview?.spending.totalCents ?? 0,
            daysLeft: daysLeft,
            firstOverCategory: over,
            isLoading: bank.isInitialLoad && bank.balanceSummary == nil,
            staleCount: staleCount,
            staleSinceSpoken: earliestStale.flatMap { ISO8601DateFormatter.dateOnly.date(from: $0) }.map { $0.formatted(.dateTime.month(.wide).day()) },
            pending: overview?.pending,
            investmentsCents: bank.investments != nil ? bank.investments?.totalCents : (investmentBalancesKnown ? Int((investments * 100).rounded()) : nil),
            investmentAccountCount: bank.investments?.accounts.count ?? investmentCount
        )
    }

    private static func isoNoFraction(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

// MARK: - Accounts list

struct AccountsListView: View {
    @Environment(BankDataManager.self) private var bankDataManager
    let onLink: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                let groups = bankDataManager.institutionGroups
                ScreenReaderSummaryHeader(
                    verdict: groups.isEmpty && bankDataManager.manualAccounts.isEmpty ? "No accounts linked" : "Accounts",
                    detail: "\(VoiceOverFormatter.count(groups.count, singular: "institution", plural: "institutions")), \(VoiceOverFormatter.count(bankDataManager.manualAccounts.count, singular: "manual account", plural: "manual accounts")). Open one to see its accounts and transactions.",
                    tone: .neutral
                )
                ForEach(groups) { group in
                    InstitutionGroupLink(group: group)
                }
                ForEach(bankDataManager.manualAccounts) { manual in
                    ManualAccountRow(account: manual)
                }
                Button(action: onLink) {
                    Label("Link another account", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Connect a bank with Plaid or add an account by hand.")
                .padding(.top, 8)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await bankDataManager.forceRefresh() }
    }
}

// MARK: - All transactions

/// "Mark as work expense" (context menu + rotor action) only for users in a
/// benefits lane; everyone else never hears about work expenses.
struct WorkExpenseRowAction: ViewModifier {
    let enabled: Bool
    let transaction: Transaction

    func body(content: Content) -> some View {
        if enabled {
            content
                .contextMenu {
                    Button { WorkExpenseHandoff.shared.offer(transaction: transaction) } label: {
                        Label("Mark as work expense", systemImage: "briefcase")
                    }
                }
                .accessibilityAction(named: "Mark as work expense") {
                    WorkExpenseHandoff.shared.offer(transaction: transaction)
                }
        } else {
            content
        }
    }
}

struct AllTransactionsView: View {
    var initial: [Transaction] = []

    @Environment(UserManager.self) private var userManager
    @Environment(BankDataManager.self) private var bankDataManager
    @State private var transactions: [Transaction] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    var body: some View {
        List {
            Section {
                if transactions.isEmpty {
                    Text(isLoading ? "Loading transactions…" : "No transactions yet. Pull down to refresh.")
                        .foregroundColor(.haloTextSecondary)
                }
                ForEach(transactions, id: \.idTransaction) { txn in
                    NavigationLink {
                        TransactionDetailView(transaction: txn)
                    } label: {
                        TransactionRow(transaction: txn, accountLabel: bankDataManager.accountLabel(for: txn.accountId))
                    }
                    .modifier(WorkExpenseRowAction(enabled: userManager.capabilities.showsBenefitsLane, transaction: txn))
                }
            } header: {
                Text("\(VoiceOverFormatter.count(transactions.count, singular: "transaction", plural: "transactions")), newest first")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Recent transactions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            transactions = initial
            await load(forceRefresh: false)
        }
        .refreshable { await load(forceRefresh: true) }
    }

    private func load(forceRefresh: Bool) async {
        isLoading = true
        defer { isLoading = false }
        let loaded = await bankDataManager.allTransactions(forceRefresh: forceRefresh)
        if !loaded.isEmpty || transactions.isEmpty { transactions = loaded }
        if forceRefresh {
            UIAccessibility.post(notification: .announcement, argument: "\(VoiceOverFormatter.count(transactions.count, singular: "transaction", plural: "transactions")) loaded.")
        }
    }
}


struct InstitutionGroup: Identifiable {
    let id: String
    let items: [ConnectedItem]
    var name: String { items.first?.institutionName ?? "Bank" }
    static func grouping(_ items: [ConnectedItem]) -> [InstitutionGroup] {
        Dictionary(grouping: items) { $0.institutionId.isEmpty ? $0.itemId : $0.institutionId }
            .map { InstitutionGroup(id: $0.key, items: $0.value.sorted { $0.itemId < $1.itemId }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension BankDataManager {
    var institutionGroups: [InstitutionGroup] {
        InstitutionGroup.grouping(linkedItems ?? [])
    }
    var hasInvestmentAccounts: Bool {
        if let investments { return (investments.linkedAccountCount ?? investments.accounts.filter { $0.source != "manual" }.count) > 0 }
        return (accountsByItemId.values.flatMap { $0 } + (accounts ?? [])).contains { $0.isActive && ["investment", "brokerage"].contains($0.type.lowercased()) }
    }
    func accounts(in group: InstitutionGroup) -> [BankAccount] {
        var seen = Set<String>()
        return group.items.flatMap { item in
            accountsByItemId[item.itemId] ?? (accounts ?? []).filter { $0.plaidItemId == item.itemId || $0.plaidItemId == item.plaidItemId }
        }.filter { $0.isActive && seen.insert($0.idAccount).inserted }
    }
}

struct InstitutionGroupLink: View {
    let group: InstitutionGroup
    @Environment(BankDataManager.self) private var bank
    var body: some View {
        if let first = group.items.first {
            NavigationLink { InstitutionGroupAccountsView(group: group) } label: {
                AccessibleInstitutionCard(item: first, accounts: bank.accounts(in: group), isLoading: false, connectionsNeedingAttention: group.items.filter { !$0.isActive }.count)
            }.buttonStyle(HapticPlainButtonStyle())
        }
    }
}

struct InstitutionGroupAccountsView: View {
    let group: InstitutionGroup
    @Environment(BankDataManager.self) private var bank
    @State private var loaded: [String: [BankAccount]] = [:]
    @State private var error: String?
    @AccessibilityFocusState private var focused: Bool
    private var accounts: [BankAccount] {
        var seen = Set<String>()
        return group.items.flatMap { loaded[$0.itemId] ?? bank.accountsByItemId[$0.itemId] ?? [] }
            .filter { $0.isActive && seen.insert($0.idAccount).inserted }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(accounts.count) accounts").font(.headline).accessibilityAddTraits(.isHeader).accessibilityFocused($focused)
                AccountIdentityReviewSection(institution: group.name)
                ForEach(accounts) { account in
                    NavigationLink {
                        AccountDetailView(account: FinancialAccount(from: account, plaidItemId: account.plaidItemId), bankAccount: account)
                    } label: { BankAccountRow(account: account) }
                    .buttonStyle(HapticPlainButtonStyle())
                }
                if let error { Text(error).foregroundStyle(Color.haloTextPrimary) }
                ForEach(Array(group.items.enumerated()), id: \.element.itemId) { index, item in
                    VStack(alignment: .leading, spacing: 8) {
                        if group.items.count > 1 { Text("Connection \(index + 1)").font(.headline) }
                        UpdateSharedAccountsButton(item: item) { await load() }
                    }
                }
            }.padding(20).padding(.bottom, 100).readableContentWidth()
        }
        .background(Color.haloBackground)
        .navigationTitle(group.name)
        .task(id: bank.identityReviews.map(\.id)) { await load(); focused = true }
        .refreshable { await load() }
    }
    private func load() async {
        if UITestArchetype.isActive { return }
        error = nil
        for item in group.items {
            do { loaded[item.itemId] = try await bank.fetchAccountsForItem(itemId: item.itemId).accounts }
            catch { self.error = "Some accounts could not refresh. Pull down to try again." }
        }
    }
}

struct InvestmentsView: View {
    @Environment(BankDataManager.self) private var bank
    @State private var error: String?
    @AccessibilityFocusState private var focused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let summary = bank.investments {
                    InvestmentPortfolioCard(summary: summary).accessibilityFocused($focused)
                    if summary.accounts.isEmpty {
                        Text("No investment accounts to show yet.").foregroundStyle(Color.haloTextSecondary)
                    } else {
                        Text("Accounts").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        ForEach(summary.sortedAccounts) { account in
                            NavigationLink {
                                InvestmentAccountView(accountId: account.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(account.institution).font(.subheadline).foregroundStyle(Color.haloTextSecondary)
                                    Text(account.name).font(.headline)
                                    if !account.mask.isEmpty { Text("Ending in \(account.mask)").font(.caption).foregroundStyle(Color.haloTextSecondary) }
                                    Text(account.formattedBalance).font(.title2.bold()).lineLimit(account.balanceCents == nil ? nil : 1).minimumScaleFactor(0.4)
                                    Text("\(account.holdings.count) \(account.holdings.count == 1 ? "holding" : "holdings") · View account").font(.subheadline).foregroundStyle(Color.haloTextSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16).haloCard()
                            }
                            .buttonStyle(HapticPlainButtonStyle())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(account.spokenName). \(account.formattedBalance). \(account.holdings.count) holdings.")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Opens investment account and holdings.")
                            .accessibilityIdentifier("investment-account-\(account.id)")
                        }
                    }
                } else if error == nil { ProgressView("Loading investments") }
                if let error { Text(error); Button("Try again") { Task { await load() } }.frame(minHeight: 44) }
            }.padding(20).padding(.bottom, 100).readableContentWidth()
        }.background(Color.haloBackground).navigationTitle("Investments").navigationBarTitleDisplayMode(.inline)
        .task { await load(); focused = true }.refreshable { await load() }
    }
    private func load() async {
        do { try await bank.loadInvestments(); error = nil }
        catch { self.error = "Could not refresh investments. Displayed values are from the last successful update." }
    }
}

struct InvestmentPortfolioCard: View {
    let summary: InvestmentSummary
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 40
    private var amount: String { summary.verifiedTotalCents.map { InvestmentSummary.money($0, currency: summary.currency) } ?? "Combined value unavailable" }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Portfolio value").font(.headline)
            if summary.verifiedTotalCents != nil {
                Text(amount).font(.haloDisplay(figureSize)).lineLimit(1).minimumScaleFactor(0.35)
            } else {
                Text(amount).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            }
            Text("Across \(summary.accounts.count) investment \(summary.accounts.count == 1 ? "account" : "accounts")")
                .font(.subheadline).foregroundStyle(Color.haloTextSecondary)
            if !summary.allocation.isEmpty {
                InvestmentAllocationGraphic(segments: summary.allocation, currency: summary.currency)
            } else if !summary.accounts.isEmpty && summary.verifiedTotalCents == nil {
                Text("See each account below for available values.").font(.subheadline).foregroundStyle(Color.haloTextSecondary)
            }
            Text("Latest reported balances").font(.caption).foregroundStyle(Color.haloTextSecondary)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color.purple.opacity(0.12), Color.haloSecondaryBackground], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.purple.opacity(0.4), lineWidth: 1))
        .foregroundStyle(Color.haloTextPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Portfolio value. \(amount). Across \(summary.accounts.count) investment accounts. Latest reported balances. Account breakdown below.")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("investment-portfolio-summary")
    }
}

/// The legend is visual; the same names and amounts are spoken by the account
/// or holding rows immediately below, so VoiceOver doesn't repeat the portfolio.
struct InvestmentAllocationGraphic: View {
    let segments: [InvestmentAllocation.Segment]
    let currency: String
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 14
    private let colors: [Color] = [.purple, .teal, .blue, .pink, .orange, .gray]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MoneySegmentsBar(amounts: segments.map(\.cents), colors: Array(colors.prefix(segments.count)), pendingIndex: -1)
                .frame(height: barHeight)
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                MoneyBarLegend(color: colors[index], text: "\(segment.label) · \(InvestmentSummary.money(segment.cents, currency: currency))")
            }
        }.accessibilityHidden(true)
    }
}

struct InvestmentAccountView: View {
    let accountId: String
    @Environment(BankDataManager.self) private var bank
    @State private var search = ""
    @State private var error: String?
    @AccessibilityFocusState private var focused: Bool
    private var account: InvestmentSummary.Account? { bank.investments?.accounts.first { $0.id == accountId } }
    private var holdings: [InvestmentSummary.Holding] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (account?.holdings ?? []).filter { query.isEmpty || $0.name.localizedStandardContains(query) || ($0.ticker?.localizedStandardContains(query) ?? false) }
            .sorted { $0.valueCents == $1.valueCents ? $0.id < $1.id : $0.valueCents > $1.valueCents }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let account {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(account.spokenName).font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityFocused($focused)
                        Text(account.formattedBalance).font(.largeTitle.bold()).lineLimit(account.balanceCents == nil ? nil : 1).minimumScaleFactor(0.4)
                        if let date = account.asOf { Text("Updated \(TabSummaries.spokenDate(String(date.prefix(10))))").font(.subheadline).foregroundStyle(Color.haloTextSecondary) }
                        if account.source == "manual" { Text("Entered manually").font(.subheadline) }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).haloCard()
                    if !account.holdingsAllocation.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Holdings breakdown").font(.headline)
                            InvestmentAllocationGraphic(segments: account.holdingsAllocation, currency: account.currency)
                            Text("Holdings are included in your account value.").font(.caption).foregroundStyle(Color.haloTextSecondary)
                        }.padding(16).haloCard().accessibilityHidden(true)
                    }
                    Text("Holdings (\(account.holdings.count))").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    if account.holdings.count > 8 {
                        TextField("Search holdings", text: $search)
                            .textFieldStyle(.roundedBorder).submitLabel(.search).autocorrectionDisabled()
                            .accessibilityLabel("Search holdings by name or symbol")
                            .accessibilityIdentifier("investment-holdings-search")
                        if !search.isEmpty { Button("Clear search") { search = "" }.frame(minHeight: 44) }
                    }
                    if holdings.isEmpty {
                        Text(search.isEmpty ? "Holdings are not available for this account yet." : "No matching holdings.").foregroundStyle(Color.haloTextSecondary)
                    }
                    ForEach(holdings) { holding in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(holding.name).font(.headline)
                            if let ticker = holding.ticker { Text(ticker).font(.subheadline).foregroundStyle(Color.haloTextSecondary) }
                            Text(InvestmentSummary.money(holding.valueCents, currency: holding.currency)).font(.title3.bold())
                            Text("\(holding.quantity.formatted()) shares or units").font(.subheadline).foregroundStyle(Color.haloTextSecondary)
                            if let date = holding.asOf { Text("Updated \(TabSummaries.spokenDate(String(date.prefix(10))))").font(.caption).foregroundStyle(Color.haloTextSecondary) }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).haloCard()
                        .accessibilityElement(children: .combine)
                    }
                } else { Text("This investment account is no longer available.") }
                if let error { Text(error) }
            }.padding(20).padding(.bottom, 80).readableContentWidth()
        }.background(Color.haloBackground).navigationTitle("Investment account").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { focused = true }
        .refreshable {
            do { try await bank.loadInvestments(); error = nil }
            catch { self.error = "Could not refresh this account. Displayed values are from the last successful update." }
        }
    }
}
