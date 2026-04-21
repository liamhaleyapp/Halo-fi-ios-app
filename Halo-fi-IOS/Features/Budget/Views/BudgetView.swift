//
//  BudgetView.swift
//  Halo-fi-IOS
//
//  The "Budget" tab — a single accessible surface combining spending,
//  monthly income, SSI monitoring, and alerts.
//
//  VoiceOver reading order: the header announcement comes first so
//  someone opening the tab hears the one number that matters (budget
//  remaining) before anything else. Then the rest of the sections in
//  natural visual order.
//

import SwiftUI

struct BudgetView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @State private var showingIncomeEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    spendingSection
                    monthlyIncomeSection
                    ssiSection
                    alertsSection
                }
                .padding()
            }
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await dataManager.refresh()
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

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        if let overview = dataManager.overview {
            VStack(alignment: .leading, spacing: 8) {
                Text(overview.month)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                headlineRemainingText(overview)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if dataManager.isLoading {
            ProgressView().frame(maxWidth: .infinity, alignment: .center)
        } else if let err = dataManager.error {
            Text(err.errorDescription ?? "Couldn't load budget.")
                .foregroundStyle(.red)
        }
    }

    private func headlineRemainingText(_ overview: BudgetOverview) -> Text {
        // Priority: show budget remaining if they have one; otherwise
        // show monthly income total so the screen still has a lead line.
        if overview.budgetStatus.hasBudget,
           let total = overview.budgetStatus.total {
            let remaining = total.formatted["remaining"] ?? "$0.00"
            return Text("\(remaining) left to spend this month")
        }
        return Text("\(overview.monthlyIncome.totalFormatted) monthly income")
    }

    @ViewBuilder
    private var spendingSection: some View {
        if let overview = dataManager.overview {
            sectionCard(title: "This month's spending") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(overview.spending.formatted["total"] ?? "$0.00")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(overview.spending.count) transactions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Spent \(overview.spending.formatted["total"] ?? "zero dollars") "
                        + "across \(overview.spending.count) transactions."
                    )

                    if !overview.spending.groups.isEmpty {
                        Divider()
                        ForEach(overview.spending.groups) { group in
                            spendingGroupRow(group)
                        }
                    }
                }
            }
        }
    }

    private func spendingGroupRow(_ group: BudgetSpendingGroup) -> some View {
        HStack {
            Text(group.key.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.subheadline)
            Spacer()
            Text(group.formatted)
                .font(.subheadline)
                .fontWeight(.medium)
            Text("\(Int(group.pctOfTotal))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(group.key.replacingOccurrences(of: "_", with: " ")): "
            + "\(group.formatted), \(Int(group.pctOfTotal)) percent of spending."
        )
    }

    @ViewBuilder
    private var monthlyIncomeSection: some View {
        if let overview = dataManager.overview {
            sectionCard(title: "Monthly income") {
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
            }
        }
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

    @ViewBuilder
    private var ssiSection: some View {
        if let ssi = dataManager.overview?.ssiStatus, ssi.hasSsi {
            sectionCard(title: "SSI monitor") {
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
                            Text(reason)
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .accessibilityLabel("Possible overpayment: \(reason)")
                    }
                }
            }
        }
    }

    private func ssiResourcesBlock(_ resources: SSIResources) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Resources")
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack {
                Text(resources.formatted["remaining"] ?? "$0.00")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                statusBadge(resources.status)
            }
            Text("out of \(resources.formatted["limit"] ?? "$0.00") limit")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(resources.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "SSI resources: \(resources.formatted["remaining"] ?? "zero") remaining "
            + "out of \(resources.formatted["limit"] ?? "two thousand dollars") limit. "
            + "Status: \(resources.status). \(resources.note)"
        )
    }

    private func ssiIncomeBlock(_ income: SSIIncome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Countable income this month")
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack {
                Text(income.formatted["countable"] ?? "$0.00")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                statusBadge(income.status)
            }
            Text("threshold \(income.formatted["threshold"] ?? "$20.00")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(income.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private func ssiNextDepositBlock(_ next: SSANextDeposit) -> some View {
        let amount = BudgetFormatter.cents(next.expectedAmountCents)
        let dateText = BudgetFormatter.friendlyDate(next.expectedDateIso) ?? next.expectedDateIso
        return VStack(alignment: .leading, spacing: 4) {
            Text("Next SSA check")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("\(amount) expected \(dateText)")
                .font(.subheadline)
            if next.confidence != "high" {
                Text("Confidence: \(next.confidence)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Next social security check: \(amount) expected \(dateText). "
            + "Confidence \(next.confidence)."
        )
    }

    @ViewBuilder
    private var alertsSection: some View {
        if let alerts = dataManager.overview?.alerts, !alerts.isEmpty {
            sectionCard(title: "Alerts") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(alerts) { alert in
                        alertRow(alert)
                    }
                }
            }
        }
    }

    private func alertRow(_ alert: BudgetAlert) -> some View {
        let readableType = alert.alertType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        let categoryText = alert.category?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        let threshold = alert.thresholdFormatted ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            Text([readableType, categoryText].compactMap { $0 }.joined(separator: ": "))
                .font(.subheadline)
                .fontWeight(.medium)
            if !threshold.isEmpty {
                Text("When \(alert.comparison) \(threshold)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Layout helpers

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusBadge(_ status: String) -> some View {
        let color = BudgetFormatter.color(forStatus: status)
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
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

    /// "2026-05-03" → "May 3" (omits year when within 12 months).
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
        case "warning": return .orange
        case "ahead", "safe": return .green
        case "on_pace": return .blue
        default: return .gray
        }
    }
}
