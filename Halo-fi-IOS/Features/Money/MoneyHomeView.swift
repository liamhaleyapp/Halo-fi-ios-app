//
//  MoneyHomeView.swift
//  Halo-fi-IOS
//
//  The Money tab (WP4): Accounts + Budget merged. Reading order for
//  VoiceOver, top to bottom:
//    a. Summary header — verdict in words, then numbers
//    b. Budget summary row → the existing BudgetView (unchanged)
//    c. Institution cards, one utterance each → existing account screens
//    d. Recent transactions (5) + "See all"; rotor "Mark as work expense"
//    e. Link another account / Add manual account
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
    @State private var recentTransactions: [Transaction] = []
    @State private var isLoadingTransactions = false
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.haloBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        header
                        budgetRow
                        institutionsSection
                        recentTransactionsSection
                        linkSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                    .readableContentWidth()
                }
                .refreshable {
                    await bankDataManager.forceRefresh()
                    await budgetDataManager.refresh()
                    await loadRecentTransactions()
                }
            }
            .navigationTitle("Money")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingLinkChooser = true } label: { Image(systemName: "plus.app") }
                        .accessibilityLabel("Add account")
                        .accessibilityHint("Opens secure bank linking flow")
                }
            }
            .sheet(isPresented: $showingLinkChooser) { LinkAccountChooserView() }
            .navigationDestination(for: ConnectedItem.self) { item in
                InstitutionAccountsView(item: item)
            }
            .navigationDestination(for: MoneyRoute.self) { route in
                switch route {
                case .budget: BudgetView()
                case .allTransactions: AllTransactionsView(transactions: recentAll)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetMoneyNavigation)) { _ in
                if !navigationPath.isEmpty { navigationPath.removeLast(navigationPath.count) }
            }
            .task {
                guard !hasAppeared else { return }
                hasAppeared = true
                await bankDataManager.refreshIfStale()
                if budgetDataManager.shouldRefresh { await budgetDataManager.refresh() }
                await loadRecentTransactions()
            }
        }
    }

    enum MoneyRoute: Hashable { case budget, allTransactions }

    // MARK: - a. Header

    var snapshot: MoneySnapshot {
        MoneySnapshot.make(bank: bankDataManager, budget: budgetDataManager)
    }

    private var summary: TabSummary {
        TabSummaries.money(snapshot, capabilities: userManager.capabilities)
    }

    private var header: some View {
        ScreenReaderSummaryHeader(
            verdict: summary.verdict,
            detail: summary.detail,
            isEstimate: summary.isEstimate,
            tone: summary.tone
        )
    }

    // MARK: - b. Budget row

    private var budgetRow: some View {
        NavigationLink(value: MoneyRoute.budget) {
            HStack(spacing: 12) {
                Image(systemName: "chart.pie.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Budget").font(.headline).foregroundColor(.haloTextPrimary)
                    Text(TabSummaries.budgetRow(snapshot))
                        .font(.subheadline)
                        .foregroundColor(.haloTextSecondary)
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
        .accessibilityLabel("Budget. \(TabSummaries.budgetRow(snapshot))")
        .accessibilityHint("Opens your budget.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - c. Institutions

    @ViewBuilder
    private var institutionsSection: some View {
        let items = bankDataManager.linkedItems ?? []
        if !items.isEmpty || !bankDataManager.manualAccounts.isEmpty {
            sectionHeader("Accounts", count: items.count + bankDataManager.manualAccounts.count)
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
        }
    }

    // MARK: - d. Recent transactions

    private var recentAll: [Transaction] { recentTransactions }

    @ViewBuilder
    private var recentTransactionsSection: some View {
        if !recentTransactions.isEmpty {
            sectionHeader("Recent transactions", count: min(5, recentTransactions.count))
            VStack(spacing: 0) {
                ForEach(recentTransactions.prefix(5), id: \.idTransaction) { txn in
                    TransactionRow(transaction: txn)
                        .padding(.horizontal, 14)
                        .contextMenu {
                            Button { markAsWorkExpense(txn) } label: {
                                Label("Mark as work expense", systemImage: "briefcase")
                            }
                        }
                        .accessibilityAction(named: "Mark as work expense") { markAsWorkExpense(txn) }
                    Divider()
                }
            }
            .background(Color.haloSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            NavigationLink(value: MoneyRoute.allTransactions) {
                Text("See all transactions")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Opens the full recent transaction list.")
        } else if isLoadingTransactions {
            ProgressView("Loading transactions…")
                .accessibilityLabel("Loading transactions")
        }
    }

    private func markAsWorkExpense(_ txn: Transaction) {
        let cents = Int((abs(txn.amount) * 100).rounded())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: String(txn.transactionDate.prefix(10))) ?? Date()
        Haptics.engine.play(.tapLight)
        WorkExpenseHandoff.shared.offer(
            WorkExpenseDraft(amountCents: cents, description: txn.merchantName ?? txn.name, occurredOn: date)
        )
    }

    private func loadRecentTransactions() async {
        isLoadingTransactions = true
        defer { isLoadingTransactions = false }
        var merged: [Transaction] = []
        for item in bankDataManager.linkedItems ?? [] {
            if let txns = try? await bankDataManager.fetchTransactionsForItem(itemId: item.itemId, forceRefresh: false) {
                merged.append(contentsOf: txns)
            }
        }
        recentTransactions = merged
            .sorted { $0.transactionDate > $1.transactionDate }
            .prefix(50)
            .map { $0 }
    }

    // MARK: - e. Link

    private var linkSection: some View {
        VStack(spacing: 10) {
            Button { showingLinkChooser = true } label: {
                Label("Link another account", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Connect a bank with Plaid or add an account by hand.")
        }
        .padding(.top, 8)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.headline).foregroundColor(.haloTextSecondary)
            Spacer()
            Text("\(count)").font(.subheadline).foregroundColor(.haloTextSecondary)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title), \(count)")
    }
}

// MARK: - Snapshot from managers

extension MoneySnapshot {
    @MainActor
    static func make(bank: BankDataManager, budget: BudgetDataManager) -> MoneySnapshot {
        var cash = 0.0
        var owed = 0.0
        var count = 0
        for account in bank.accountsByItemId.values.flatMap({ $0 }) where account.isActive {
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

// MARK: - All transactions

struct AllTransactionsView: View {
    let transactions: [Transaction]

    var body: some View {
        List {
            ForEach(transactions, id: \.idTransaction) { txn in
                TransactionRow(transaction: txn)
                    .accessibilityAction(named: "Mark as work expense") {
                        let cents = Int((abs(txn.amount) * 100).rounded())
                        WorkExpenseHandoff.shared.offer(
                            WorkExpenseDraft(amountCents: cents, description: txn.merchantName ?? txn.name, occurredOn: Date())
                        )
                    }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Recent transactions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
