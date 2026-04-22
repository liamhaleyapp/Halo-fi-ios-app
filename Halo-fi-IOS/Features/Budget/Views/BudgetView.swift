//
//  BudgetView.swift
//  Halo-fi-IOS
//
//  The "Budget" tab — monthly spending, income (editable), SSI monitoring
//  (gated on receives_ssi), and alerts.
//
//  Layout (top → bottom):
//   1. Month subtitle
//   2. Hero progress card — "Spent so far / of $X monthly budget" with
//      progress bar, % used chip, and remaining legend. Falls back to a
//      spending-only card when no budget is set.
//   3. Category alert row — only if one or more categories are over/behind.
//   4. Spending by category — tappable rows (NavigationLink to
//      BudgetCategoryDetailView). When no budget is set, shows
//      spending-only rows (non-tappable).
//   5. Monthly income card — editable via sheet.
//   6. SSI monitor — only when user.receives_ssi.
//   7. Alerts — configured user alerts from the backend.
//
//  Accessibility: every card combines children into a single VoiceOver
//  element with a natural-language label. Section headers use
//  .accessibilityAddTraits(.isHeader) so VoiceOver rotor jumps work.
//

import SwiftUI

struct BudgetView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @State private var showingIncomeEditor = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let overview = dataManager.overview {
                            monthSubtitle(overview)
                            heroCard(overview)
                            if let alertText = topCategoryAlert(overview) {
                                categoryAlertRow(alertText)
                            }
                            spendingByCategorySection(overview)
                            monthlyIncomeSection(overview)
                            ssiSection(overview.ssiStatus)
                            alertsSection(overview.alerts)
                        } else if dataManager.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 40)
                        } else if let err = dataManager.error {
                            errorView(err)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                }
                .refreshable { await dataManager.refresh() }
            }
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: BudgetStatusCategory.self) { category in
                BudgetCategoryDetailView(category: category)
            }
            .task {
                if dataManager.overview == nil {
                    await dataManager.refresh()
                }
            }
            .sheet(isPresented: $showingIncomeEditor) {
                IncomeEditorView()
            }
        }
    }

    // MARK: - Header

    private func monthSubtitle(_ overview: BudgetOverview) -> some View {
        Text(overview.month)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(overview.month) budget")
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Hero

    @ViewBuilder
    private func heroCard(_ overview: BudgetOverview) -> some View {
        if overview.budgetStatus.hasBudget, let total = overview.budgetStatus.total {
            BudgetHeroCard(total: total)
        } else {
            NoBudgetHeroCard(spending: overview.spending)
        }
    }

    // MARK: - Category alert

    private func topCategoryAlert(_ overview: BudgetOverview) -> String? {
        guard overview.budgetStatus.hasBudget else { return nil }
        // Pick the first category that's over / behind; mockup shows one at a time.
        let problem = overview.budgetStatus.categories.first {
            $0.status == "over" || $0.status == "behind"
        }
        guard let cat = problem else { return nil }
        let name = BudgetFormatter.displayName(forCategory: cat.category)
        let pct = Int(cat.pctUsed.rounded())
        return "\(name) is \(pct)% of budget"
    }

    private func categoryAlertRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: \(text)")
    }

    // MARK: - Spending by category

    @ViewBuilder
    private func spendingByCategorySection(_ overview: BudgetOverview) -> some View {
        if overview.budgetStatus.hasBudget, !overview.budgetStatus.categories.isEmpty {
            budgetGroupedSections(overview.budgetStatus.categories)
        } else if !overview.spending.groups.isEmpty {
            // No budget set — show spending totals only, non-tappable.
            Section {
                ForEach(overview.spending.groups) { group in
                    BudgetSpendingOnlyRow(group: group)
                }
            } header: {
                sectionHeader("Spending by Category", count: overview.spending.groups.count)
            }
        }
    }

    /// Group budget categories into status-ordered sections (Over → Behind
    /// → On Pace → Ahead). Mirrors AccountsOverviewView's "Connected" /
    /// "Needs Attention" grouping so the Budget tab reads consistently.
    @ViewBuilder
    private func budgetGroupedSections(_ categories: [BudgetStatusCategory]) -> some View {
        let grouped = Dictionary(grouping: categories, by: { $0.status })
        let ordering: [(status: String, title: String)] = [
            ("over",    "Over Budget"),
            ("behind",  "Behind"),
            ("on_pace", "On Pace"),
            ("ahead",   "Ahead"),
        ]

        ForEach(ordering, id: \.status) { group in
            if let rows = grouped[group.status], !rows.isEmpty {
                Section {
                    ForEach(rows) { cat in
                        NavigationLink(value: cat) {
                            BudgetCategoryRow(category: cat)
                        }
                        .buttonStyle(HapticPlainButtonStyle())
                    }
                } header: {
                    sectionHeader(group.title, count: rows.count)
                }
            }
        }
    }

    // MARK: - Monthly income

    @ViewBuilder
    private func monthlyIncomeSection(_ overview: BudgetOverview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(overview.monthlyIncome.totalFormatted)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Edit") { showingIncomeEditor = true }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Edit monthly income")
                }
                incomeSourceRows(overview.monthlyIncome.sources)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        } header: {
            sectionHeader("Monthly Income", count: activeIncomeSourceCount(overview.monthlyIncome.sources))
        }
    }

    private func activeIncomeSourceCount(_ sources: MonthlyIncomeSources) -> Int {
        var n = 0
        if let c = sources.paycheck.monthlyCents, c > 0 { n += 1 }
        if sources.ssi.enabled, let c = sources.ssi.amountCents, c > 0 { n += 1 }
        if sources.ssdi.enabled, let c = sources.ssdi.amountCents, c > 0 { n += 1 }
        return n
    }

    @ViewBuilder
    private func incomeSourceRows(_ sources: MonthlyIncomeSources) -> some View {
        if let monthly = sources.paycheck.monthlyCents, monthly > 0 {
            incomeRow(
                label: sources.paycheck.name ?? "Paycheck",
                amount: BudgetFormatter.cents(monthly),
                detail: sources.paycheck.frequency
            )
        }
        if sources.ssi.enabled, let cents = sources.ssi.amountCents, cents > 0 {
            incomeRow(label: "SSI", amount: BudgetFormatter.cents(cents), detail: "monthly")
        }
        if sources.ssdi.enabled, let cents = sources.ssdi.amountCents, cents > 0 {
            incomeRow(label: "SSDI", amount: BudgetFormatter.cents(cents), detail: "monthly")
        }
    }

    private func incomeRow(label: String, amount: String, detail: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(amount).font(.subheadline).fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(amount)\(detail.map { ", \($0)" } ?? "")")
    }

    // MARK: - SSI

    @ViewBuilder
    private func ssiSection(_ ssi: SSIStatus) -> some View {
        if ssi.hasSsi {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    if let resources = ssi.resources {
                        ssiResourcesBlock(resources)
                    }
                    if let income = ssi.income {
                        ssiIncomeBlock(income)
                    }
                    if let next = ssi.nextSsaDeposit {
                        ssiNextDepositBlock(next)
                    }
                    if ssi.overpaymentFlag == true, let reason = ssi.overpaymentReason {
                        Label {
                            Text(reason).font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .accessibilityLabel("Possible overpayment: \(reason)")
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            } header: {
                sectionHeader("SSI Monitor", count: ssiSectionCount(ssi))
            }
        }
    }

    private func ssiSectionCount(_ ssi: SSIStatus) -> Int {
        var n = 0
        if ssi.resources != nil { n += 1 }
        if ssi.income != nil { n += 1 }
        if ssi.nextSsaDeposit != nil { n += 1 }
        return n
    }

    private func ssiResourcesBlock(_ r: SSIResources) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Resources")
                .font(.subheadline).fontWeight(.semibold)
            HStack {
                Text(r.formatted["remaining"] ?? "$0.00")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                statusBadge(r.status)
            }
            Text("out of \(r.formatted["limit"] ?? "$0.00") limit")
                .font(.caption).foregroundStyle(.secondary)
            Text(r.note)
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("""
            SSI resources: \(r.formatted["remaining"] ?? "zero") remaining \
            of \(r.formatted["limit"] ?? "zero") limit. \
            Status: \(r.status). \(r.note)
            """)
    }

    private func ssiIncomeBlock(_ income: SSIIncome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Countable income this month")
                .font(.subheadline).fontWeight(.semibold)
            HStack {
                Text(income.formatted["countable"] ?? "$0.00")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                statusBadge(income.status)
            }
            Text("threshold \(income.formatted["threshold"] ?? "$20.00")")
                .font(.caption).foregroundStyle(.secondary)
            Text(income.note)
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private func ssiNextDepositBlock(_ next: SSANextDeposit) -> some View {
        let amount = BudgetFormatter.cents(next.expectedAmountCents)
        let dateText = BudgetFormatter.friendlyDate(next.expectedDateIso) ?? next.expectedDateIso
        return VStack(alignment: .leading, spacing: 4) {
            Text("Next SSA check").font(.subheadline).fontWeight(.semibold)
            Text("\(amount) expected \(dateText)").font(.subheadline)
            if next.confidence != "high" {
                Text("Confidence: \(next.confidence)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next social security check: \(amount) expected \(dateText). Confidence \(next.confidence).")
    }

    // MARK: - Alerts

    @ViewBuilder
    private func alertsSection(_ alerts: [BudgetAlert]) -> some View {
        if !alerts.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(alerts) { alert in
                        alertRow(alert)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            } header: {
                sectionHeader("Alerts", count: alerts.count)
            }
        }
    }

    private func alertRow(_ alert: BudgetAlert) -> some View {
        let readableType = alert.alertType.replacingOccurrences(of: "_", with: " ").capitalized
        let categoryText = alert.category
            .map { BudgetFormatter.displayName(forCategory: $0) }
        let threshold = alert.thresholdFormatted ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            Text([readableType, categoryText].compactMap { $0 }.joined(separator: ": "))
                .font(.subheadline).fontWeight(.medium)
            if !threshold.isEmpty {
                Text("When \(alert.comparison) \(threshold)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Layout helpers

    /// Same look as AccountsOverviewView.sectionHeader — headline + count
    /// right-aligned in muted gray. Keeps the two tabs visually consistent.
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.gray)
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.7))
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title), \(count) item\(count == 1 ? "" : "s")")
    }

    private func sectionCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func statusBadge(_ status: String) -> some View {
        let color = BudgetFormatter.color(forStatus: status)
        return Text(BudgetFormatter.prettyStatus(status))
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }

    private func errorView(_ err: BudgetError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(err.errorDescription ?? "Couldn't load budget.")
                .font(.subheadline)
                .foregroundStyle(.red)
            Button("Retry") {
                Task { await dataManager.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Hero cards

private struct BudgetHeroCard: View {
    let total: BudgetStatusTotal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent so far")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(total.formatted["spent"] ?? "$0.00")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                    Text("of \(total.formatted["limit"] ?? "$0.00") monthly budget")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
                pctChip
            }
            progressBar
            legend
        }
        .padding(18)
        .background(heroGradient, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var pctChip: some View {
        Text("\(Int(total.pctUsed.rounded()))% used")
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.22), in: Capsule())
            .foregroundStyle(.white)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let pct = min(max(total.pctUsed / 100.0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(progressColor)
                    .frame(width: geo.size.width * CGFloat(pct))
            }
        }
        .frame(height: 8)
    }

    private var legend: some View {
        HStack {
            Text("$0")
            Spacer()
            Text("\(total.formatted["remaining"] ?? "$0.00") remaining")
            Spacer()
            Text(total.formatted["limit"] ?? "$0.00")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.75))
    }

    private var progressColor: Color {
        switch total.status {
        case "over":     return Color(red: 1.00, green: 0.45, blue: 0.35)
        case "behind":   return Color(red: 1.00, green: 0.65, blue: 0.25)
        case "ahead":    return Color(red: 0.40, green: 0.85, blue: 0.55)
        default:         return Color(red: 0.95, green: 0.80, blue: 0.35)
        }
    }

    private var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.16, green: 0.22, blue: 0.48),
                Color(red: 0.10, green: 0.14, blue: 0.32),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accessibilityLabel: String {
        let spent = total.formatted["spent"] ?? "zero dollars"
        let limit = total.formatted["limit"] ?? "zero dollars"
        let remaining = total.formatted["remaining"] ?? "zero dollars"
        let pct = Int(total.pctUsed.rounded())
        let status = total.status.replacingOccurrences(of: "_", with: " ")
        return "Budget this month. Spent \(spent) of \(limit) monthly budget. \(pct) percent used. \(remaining) remaining. Status: \(status)."
    }
}

private struct NoBudgetHeroCard: View {
    let spending: BudgetSpending

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spent this month")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            Text(spending.formatted["total"] ?? "$0.00")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
            Text("Set up a budget to track progress — ask Halo to get started.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.55), Color.blue.opacity(0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spent \(spending.formatted["total"] ?? "zero dollars") this month. No budget set yet.")
    }
}

// MARK: - Category row (tappable)

private struct BudgetCategoryRow: View {
    let category: BudgetStatusCategory

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(BudgetFormatter.displayName(forCategory: category.category))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(category.formatted["spent"] ?? "$0.00")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("of \(category.formatted["limit"] ?? "$0.00")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                progressBar
            }
            pctLabel
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to see category details.")
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(BudgetFormatter.color(forCategory: category.category).opacity(0.22))
                .frame(width: 36, height: 36)
            Image(systemName: BudgetFormatter.iconName(forCategory: category.category))
                .foregroundStyle(BudgetFormatter.color(forCategory: category.category))
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let pct = min(max(category.pctUsed / 100.0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemBackground))
                Capsule()
                    .fill(BudgetFormatter.color(forCategory: category.category))
                    .frame(width: geo.size.width * CGFloat(pct))
            }
        }
        .frame(height: 4)
    }

    private var pctLabel: some View {
        Text("\(Int(category.pctUsed.rounded()))%")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(BudgetFormatter.color(forStatus: category.status))
            .frame(minWidth: 36, alignment: .trailing)
    }

    private var accessibilityLabel: String {
        let name = BudgetFormatter.displayName(forCategory: category.category)
        let spent = category.formatted["spent"] ?? "zero dollars"
        let limit = category.formatted["limit"] ?? "zero dollars"
        let pct = Int(category.pctUsed.rounded())
        let status = category.status.replacingOccurrences(of: "_", with: " ")
        return "\(name): \(spent) of \(limit), \(pct) percent used. Status: \(status)."
    }
}

// MARK: - Spending-only row (no budget set)

private struct BudgetSpendingOnlyRow: View {
    let group: BudgetSpendingGroup

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(BudgetFormatter.color(forCategory: group.key).opacity(0.22))
                    .frame(width: 36, height: 36)
                Image(systemName: BudgetFormatter.iconName(forCategory: group.key))
                    .foregroundStyle(BudgetFormatter.color(forCategory: group.key))
            }
            Text(BudgetFormatter.displayName(forCategory: group.key))
                .font(.subheadline)
            Spacer()
            Text(group.formatted)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("\(Int(group.pctOfTotal.rounded()))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(BudgetFormatter.displayName(forCategory: group.key)): \(group.formatted), \(Int(group.pctOfTotal.rounded())) percent of spending.")
    }
}

// MARK: - Shared formatting

enum BudgetFormatter {
    static func cents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? "$0.00"
    }

    static func friendlyDate(_ iso: String) -> String? {
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = isoFormatter.date(from: iso) else { return nil }
        let display = DateFormatter()
        display.dateFormat = "MMMM d"
        return display.string(from: date)
    }

    static func color(forStatus status: String) -> Color {
        switch status {
        case "over", "behind": return .red
        case "warning":        return .orange
        case "ahead", "safe":  return .green
        case "on_pace":        return .blue
        default:               return .gray
        }
    }

    static func prettyStatus(_ status: String) -> String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Category visuals
    //
    // Display names match Plaid's Personal Finance Category (PFC) taxonomy
    // exactly — "Food and Drink", not "Food & Drink"; "General Merchandise",
    // not "Shopping"; "General Services", not "Subscriptions". Keeping the
    // naming consistent with Plaid avoids divergence between what the voice
    // agent says and what the UI displays.

    static func displayName(forCategory key: String) -> String {
        switch key {
        case "income":                   return "Income"
        case "transfer_in":              return "Transfer In"
        case "transfer_out":             return "Transfer Out"
        case "loan_payments":            return "Loan Payments"
        case "bank_fees":                return "Bank Fees"
        case "entertainment":            return "Entertainment"
        case "food_and_drink":           return "Food and Drink"
        case "general_merchandise":      return "General Merchandise"
        case "home_improvement":         return "Home Improvement"
        case "medical":                  return "Medical"
        case "personal_care":            return "Personal Care"
        case "general_services":         return "General Services"
        case "government_and_non_profit":return "Government and Non-Profit"
        case "transportation":           return "Transportation"
        case "travel":                   return "Travel"
        case "rent_and_utilities":       return "Rent and Utilities"
        case "uncategorized":            return "Uncategorized"
        default:
            return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func iconName(forCategory key: String) -> String {
        switch key {
        case "income":                    return "arrow.down.circle.fill"
        case "transfer_in",
             "transfer_out":              return "arrow.left.arrow.right"
        case "loan_payments":             return "building.columns.fill"
        case "bank_fees":                 return "dollarsign.circle.fill"
        case "entertainment":             return "sparkles.tv.fill"
        case "food_and_drink":            return "fork.knife"
        case "general_merchandise":       return "bag.fill"
        case "home_improvement":          return "hammer.fill"
        case "medical":                   return "cross.case.fill"
        case "personal_care":             return "heart.fill"
        case "general_services":          return "square.grid.2x2.fill"
        case "government_and_non_profit": return "building.2.fill"
        case "transportation":            return "car.fill"
        case "travel":                    return "airplane"
        case "rent_and_utilities":        return "house.fill"
        default:                          return "circle.dotted"
        }
    }

    static func color(forCategory key: String) -> Color {
        switch key {
        case "income":                    return .green
        case "transfer_in",
             "transfer_out":              return .gray
        case "loan_payments":             return .red
        case "bank_fees":                 return .red
        case "entertainment":             return .indigo
        case "food_and_drink":            return .orange
        case "general_merchandise":       return .pink
        case "home_improvement":          return .brown
        case "medical":                   return .teal
        case "personal_care":             return .mint
        case "general_services":          return .purple
        case "government_and_non_profit": return .blue
        case "transportation":            return .yellow
        case "travel":                    return .cyan
        case "rent_and_utilities":        return .blue
        default:                          return .secondary
        }
    }
}
