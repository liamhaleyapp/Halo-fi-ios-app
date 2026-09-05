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
                    LazyVStack(spacing: 12) {
                        header
                        AttentionStack(
                            cards: budgetDataManager.attentionCards,
                            moreCount: budgetDataManager.attentionMoreCount,
                            isRefreshing: budgetDataManager.isLoading,
                            onOpen: { open($0) },
                            onNotNow: { card in Task { await budgetDataManager.dismissCard(card) } }
                        )
                        budgetRow
                        incomeRow
                        billsRow
                        accountsRow
                        transactionsRow
                        linkSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                    .readableContentWidth()
                }
                .refreshable {
                    // Bank + budget in parallel; transactions after the bank
                    // (they need the linked items).
                    async let bank: () = bankDataManager.forceRefresh()
                    async let budget: () = budgetDataManager.refresh()
                    _ = await (bank, budget)
                    await loadTransactions(forceRefresh: true)
                }
            }
            .navigationTitle("Money")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingLinkChooser) { LinkAccountChooserView() }
            .navigationDestination(for: ConnectedItem.self) { item in
                InstitutionAccountsView(item: item)
            }
            .navigationDestination(for: MoneyRoute.self) { route in
                switch route {
                case .budget: BudgetView()
                case .accounts: AccountsListView(onLink: { showingLinkChooser = true })
                case .allTransactions: AllTransactionsView(initial: recentTransactions)
                case .resourceMonitor: ResourceMonitorView()
                case .income: IncomeView()
                case .bills: BillsView()
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
                        try await budgetDataManager.confirmSSIDeduction(candidate: candidate, as: type)
                        budgetDataManager.resolveCard(card)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetMoneyNavigation)) { _ in
                if !navigationPath.isEmpty { navigationPath.removeLast(navigationPath.count) }
            }
            .task {
                guard !hasAppeared else { return }
                hasAppeared = true
                await bankDataManager.refreshIfStale()
                // The header sums the per-institution accounts — the same
                // source the Accounts page shows — so the figure never shifts
                // as caches fill. First launch: load them if nothing is cached.
                if bankDataManager.accountsByItemId.isEmpty, !(bankDataManager.linkedItems ?? []).isEmpty {
                    await bankDataManager.forceRefresh()
                }
                if budgetDataManager.shouldRefresh { await budgetDataManager.refresh() }
                await loadTransactions(forceRefresh: false)
            }
        }
    }

    enum MoneyRoute: Hashable {
        case budget, accounts, allTransactions, resourceMonitor, income, bills, workExpenses
        case package(String?)
        case review(String)
    }

    // MARK: - Attention actions

    private func open(_ card: AttentionCard) {
        switch card.actionType {
        case "label_deposit", "enter_gross": labelCard = card
        case "confirm_bill": billCard = card
        case "apply_budget_suggestion": suggestionCard = card
        case "open_budget": navigationPath.append(MoneyRoute.budget)
        case "open_benefits_profile": navigationPath.append(BenefitsHomeView.Route.benefitsProfile)
        case "confirm_candidate": candidateCard = card
        case "open_resource_monitor": navigationPath.append(MoneyRoute.resourceMonitor)
        case "open_package": navigationPath.append(MoneyRoute.package(card.payload.month))
        case "open_review": navigationPath.append(MoneyRoute.review(card.payload.month ?? MonthKey.current))
        case "open_work_expenses": navigationPath.append(MoneyRoute.workExpenses)
        case "open_accounts": navigationPath.append(MoneyRoute.accounts)
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

    // MARK: - b. Budget row

    private var budgetRow: some View {
        row(title: "Budget", icon: "chart.pie.fill", tint: .blue, line: TabSummaries.budgetRow(snapshot),
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
                if s.workIncomeGrossCents > 0 { text += ", \(BudgetFormatter.cents(s.workIncomeGrossCents)) gross this month" }
                if s.paychecksNeedingGross > 0 { text += ", \(VoiceOverFormatter.count(s.paychecksNeedingGross, singular: "paystub gross", plural: "paystub grosses")) still needed" }
                return text + "."
            }
            if !s.sources.isEmpty { return "\(VoiceOverFormatter.count(s.sources.count, singular: "payer", plural: "payers")) learned. No work income labeled yet." }
            return "What your deposits are, learned as they arrive."
        }()
        return row(title: "Income", icon: "arrow.down.circle.fill", tint: .indigo, line: line,
                   hint: "Opens where your money comes from, this month's work income, and the amounts you told HaloFi.", route: .income)
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
            var text = "\(VoiceOverFormatter.count(confirmed.count, singular: "bill", plural: "bills")), about \(VoiceOverFormatter.dollars(b.monthlyBillsCents)) a month."
            if let next = confirmed.compactMap({ s in s.nextExpected.map { ($0, s.merchant) } }).min(by: { $0.0 < $1.0 }) {
                text += " Next: \(next.1), \(TabSummaries.spokenDate(next.0))."
            }
            if unanswered > 0 { text += " \(unanswered) to answer." }
            return text
        }()
        return row(title: "Bills", icon: "calendar.badge.clock", tint: .teal, line: line,
                   hint: "Opens your recurring charges: answer which are bills; they count in what is left by the 1st.", route: .bills)
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
            let names = items.map(\.institutionName)
            line = VoiceOverFormatter.count(snapshot.accountCount, singular: "account", plural: "accounts")
            if !names.isEmpty { line += " at " + names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " and more" : "") }
            if manual > 0 { line += ", plus \(VoiceOverFormatter.count(manual, singular: "manual account", plural: "manual accounts"))" }
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
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundColor(.haloTextPrimary)
                    Text(line).font(.subheadline).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.haloTextTertiary).accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 64)
            .background(Color.haloSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(HapticPlainButtonStyle())
        .accessibilityElement(children: .ignore)
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
    @MainActor
    static func make(bank: BankDataManager, budget: BudgetDataManager) -> MoneySnapshot {
        var cash = 0.0
        var owed = 0.0
        var count = 0
        // Single source: the per-institution accounts (what the Accounts page
        // lists). The flat /bank/accounts list is only a stopgap before the
        // first per-item load completes.
        let perItem = bank.accountsByItemId.values.flatMap { $0 }
        let source = perItem.isEmpty ? (bank.accounts ?? []) : perItem
        // Dedupe by account id: three feeds write accountsByItemId and a
        // stale or doubled entry must never change the headline number.
        var seenIds = Set<String>()
        for account in source where account.isActive && seenIds.insert(account.idAccount).inserted {
            count += 1
            let balance = account.currentBalance ?? 0
            if account.type.lowercased() == "credit" || account.type.lowercased() == "loan" {
                owed += max(0, balance)
            } else {
                cash += max(0, balance)
            }
        }
        for manual in bank.manualAccounts {
            count += 1
            let kind = String(describing: manual.accountType).lowercased()
            if kind.contains("credit") || kind.contains("loan") {
                owed += max(0, manual.balance)
            } else {
                cash += max(0, manual.balance)
            }
        }
        let attention = (bank.linkedItems ?? []).filter { !$0.isActive }.count
        let overview = budget.overview
        var daysLeft: Int?
        if let end = overview?.period.endUtc, let endDate = ISO8601DateFormatter().date(from: end) ?? isoNoFraction(end) {
            daysLeft = max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
        }
        let over = overview?.budgetStatus.categories.first(where: { $0.status == "over" })
            .map { BudgetFormatter.displayName(forCategory: $0.category) }
        return MoneySnapshot(
            cashCents: Int((cash * 100).rounded()),
            owedCents: Int((owed * 100).rounded()),
            accountCount: count,
            connectionsNeedingAttention: attention,
            resources: overview?.ssiStatus.resources,
            budgetTotal: overview?.budgetStatus.hasBudget == true ? overview?.budgetStatus.total : nil,
            spentCents: overview?.spending.totalCents ?? 0,
            daysLeft: daysLeft,
            firstOverCategory: over
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
                let items = bankDataManager.linkedItems ?? []
                ScreenReaderSummaryHeader(
                    verdict: items.isEmpty && bankDataManager.manualAccounts.isEmpty ? "No accounts linked" : "Accounts",
                    detail: "\(VoiceOverFormatter.count(items.count, singular: "institution", plural: "institutions")), \(VoiceOverFormatter.count(bankDataManager.manualAccounts.count, singular: "manual account", plural: "manual accounts")). Open one to see its accounts and transactions.",
                    tone: .neutral
                )
                ForEach(items, id: \.itemId) { item in
                    NavigationLink(value: item) {
                        AccessibleInstitutionCard(
                            item: item,
                            accounts: bankDataManager.accountsByItemId[item.itemId],
                            isLoading: false
                        )
                    }
                    .buttonStyle(HapticPlainButtonStyle())
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
