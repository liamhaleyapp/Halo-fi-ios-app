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

    var body: some View {
        // All-closure-based NavigationLinks (no path binding, no
        // navigationDestination registration). Mixing value-based
        // NavigationLink(value:) with closure-based pushes confuses
        // SwiftUI's stack reconciliation — the user saw category drill-
        // downs flash and immediately bounce back to the list.
        NavigationStack {
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
                            breakdownByCategoryButton(overview)
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

    /// Single row that pushes BudgetCategoryListView. Replaces the inline
    /// category grid — keeps the main Budget tab short + scannable.
    @ViewBuilder
    private func breakdownByCategoryButton(_ overview: BudgetOverview) -> some View {
        let count = breakdownCount(overview)
        if count > 0 {
            NavigationLink {
                BudgetCategoryListView()
            } label: {
                BreakdownByCategoryRow(
                    count: count,
                    hasBudget: overview.budgetStatus.hasBudget
                )
            }
            .buttonStyle(HapticPlainButtonStyle())
        }
    }

    private func breakdownCount(_ overview: BudgetOverview) -> Int {
        if overview.budgetStatus.hasBudget {
            return overview.budgetStatus.categories.count
        }
        return overview.spending.groups.count
    }

    // MARK: - Monthly income

    @ViewBuilder
    private func monthlyIncomeSection(_ overview: BudgetOverview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                // Total + edit affordance — pencil icon instead of the
                // bordered button, which felt inconsistent with the flat
                // dark-card aesthetic of the surrounding sections.
                HStack(alignment: .firstTextBaseline) {
                    Text(overview.monthlyIncome.totalFormatted)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Total monthly income: \(overview.monthlyIncome.totalFormatted)")
                    Spacer(minLength: 0)
                    Button {
                        showingIncomeEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color(.tertiarySystemBackground), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit monthly income")
                    .accessibilityHint("Opens the income editor")
                }
                .padding(.bottom, 12)

                if activeIncomeSourceCount(overview.monthlyIncome.sources) > 0 {
                    Divider()
                        .padding(.bottom, 12)
                    incomeSourceRows(overview.monthlyIncome.sources)
                }
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
        VStack(spacing: 14) {
            if let monthly = sources.paycheck.monthlyCents, monthly > 0 {
                incomeRow(
                    label: sources.paycheck.name ?? "Paycheck",
                    amount: BudgetFormatter.cents(monthly),
                    detail: friendlyFrequency(sources.paycheck.frequency)
                )
            }
            if sources.ssi.enabled, let cents = sources.ssi.amountCents, cents > 0 {
                incomeRow(label: "SSI", amount: BudgetFormatter.cents(cents), detail: "Monthly")
            }
            if sources.ssdi.enabled, let cents = sources.ssdi.amountCents, cents > 0 {
                incomeRow(label: "SSDI", amount: BudgetFormatter.cents(cents), detail: "Monthly")
            }
        }
    }

    private func incomeRow(label: String, amount: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(amount)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(amount)\(detail.map { ", \($0.lowercased())" } ?? "")")
    }

    /// Map the raw API frequency value into a human-friendly label that
    /// matches the picker copy in IncomeEditorView ("biweekly" →
    /// "Every two weeks"). Falls back to the raw value if unknown.
    private func friendlyFrequency(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "weekly":        return "Weekly"
        case "biweekly":      return "Every two weeks"
        case "twice_monthly": return "Twice a month"
        case "monthly":       return "Monthly"
        case "irregular":     return "Irregular"
        default:              return raw.capitalized
        }
    }

    // MARK: - SSI

    @ViewBuilder
    private func ssiSection(_ ssi: SSIStatus) -> some View {
        if ssi.hasSsi {
            Section {
                VStack(spacing: 12) {
                    if let resources = ssi.resources {
                        SSIResourceHeroCard(resources: resources)
                    }
                    if let income = ssi.income {
                        SSIIncomeHeroCard(income: income)
                    }
                    if let next = ssi.nextSsaDeposit {
                        SSINextDepositCard(next: next)
                    }
                    if ssi.overpaymentFlag == true, let reason = ssi.overpaymentReason {
                        SSIOverpaymentBanner(reason: reason)
                    }
                    if !data.ssiCandidates.isEmpty {
                        SSIDeductionCandidatesCard(
                            candidates: data.ssiCandidates,
                            onConfirm: { candidate, type in
                                do {
                                    try await data.confirmSSIDeduction(
                                        candidate: candidate, as: type
                                    )
                                } catch {
                                    // Soft-fail; data manager already logged.
                                }
                            }
                        )
                    }
                }
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

// MARK: - SSI hero cards
//
// All four use a navy gradient that matches BudgetHeroCard so the SSI
// section reads as the b-side of the same visual system. Status pills
// + progress bars carry the safe/warning/over signal so VoiceOver users
// hear the same band the visual conveys.

private let ssiHeroGradient = LinearGradient(
    colors: [
        Color(red: 0.16, green: 0.22, blue: 0.48),
        Color(red: 0.10, green: 0.14, blue: 0.32),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private struct SSIResourceHeroCard: View {
    let resources: SSIResources

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resources remaining")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.SSI.subtextBright)
                    Text(resources.formatted["remaining"] ?? "$0.00")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                    Text("out of \(resources.formatted["limit"] ?? "$0.00") limit")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.SSI.subtextBright)
                }
                Spacer(minLength: 0)
                SSIStatusChip(status: chipStatus)
            }
            SSIProgressBar(pctUsed: resources.pctUsed, status: resources.status)
            if let exclusionLine = exclusionBreakdownLine {
                Text(exclusionLine)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.SSI.subtextBright)
            }
            Text(resources.note)
                .font(.caption2)
                .foregroundStyle(DesignTokens.SSI.subtextSecondary)
        }
        .padding(18)
        .background(ssiHeroGradient, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Prefer the engine-derived v2 status when present (over | critical
    /// | warning | ok). Falls back to the legacy v1 (safe | warning |
    /// over) when v2 fields haven't been populated.
    private var chipStatus: String {
        resources.v2Status ?? resources.status
    }

    /// "Excluded $99,500 (ABLE $99,000, Burial $500)" — only shown
    /// when v2 produced a non-zero exclusion. Skipped in v1 mode.
    private var exclusionBreakdownLine: String? {
        guard let excluded = resources.excludedCents, excluded > 0 else { return nil }
        var parts: [String] = []
        if let cents = resources.ableBalanceCents, cents > 0 {
            parts.append("ABLE \(BudgetFormatter.cents(min(cents, 10_000_000)))")
        }
        if let cents = resources.burialFundCents, cents > 0 {
            parts.append("Burial \(BudgetFormatter.cents(cents))")
        }
        let suffix = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "Excluded \(BudgetFormatter.cents(excluded))\(suffix)"
    }

    private var accessibilityLabel: String {
        let remaining = resources.formatted["remaining"] ?? "zero dollars"
        let limit = resources.formatted["limit"] ?? "zero dollars"
        let pct = Int(resources.pctUsed.rounded())
        let status = chipStatus.replacingOccurrences(of: "_", with: " ")
        var parts = [
            "SSI resources. \(remaining) remaining out of \(limit) limit. \(pct) percent used. Status: \(status)."
        ]
        if let line = exclusionBreakdownLine { parts.append(line + ".") }
        parts.append(resources.note)
        return parts.joined(separator: " ")
    }
}

private struct SSIIncomeHeroCard: View {
    let income: SSIIncome

    var body: some View {
        if let projectedCents = income.projectedPaymentCents {
            v2Body(projectedCents: projectedCents)
        } else {
            legacyBody
        }
    }

    // MARK: - Engine v2 — projected SSI is the headline
    @ViewBuilder
    private func v2Body(projectedCents: Int) -> some View {
        let projected = BudgetFormatter.cents(projectedCents)
        let fbr = BudgetFormatter.cents(income.fbrCents ?? 0)
        let countableTotal = (income.countableEarnedCents ?? 0)
            + (income.countableUnearnedCents ?? 0)
        let countableStr = BudgetFormatter.cents(countableTotal)
        let v2Status = SSIIncomeHeroCard.deriveV2Status(income: income)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projected SSI this month")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.SSI.subtextBright)
                    Text(projected)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                    Text("FBR \(fbr) minus \(countableStr) countable")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.SSI.subtextBright)
                }
                Spacer(minLength: 0)
                SSIStatusChip(status: v2Status)
            }
            if let earnRoomCents = income.earnRoomGrossCents {
                Text(earnRoomNarrative(earnRoomCents: earnRoomCents))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.SSI.subtextBright)
            }
            if let v2Note = income.v2Note {
                Text(v2Note)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.SSI.subtextSecondary)
            }
        }
        .padding(18)
        .background(ssiHeroGradient, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(v2AccessibilityLabel(
            projected: projected,
            v2Status: v2Status
        ))
    }

    private func earnRoomNarrative(earnRoomCents: Int) -> String {
        let amount = BudgetFormatter.cents(abs(earnRoomCents))
        if earnRoomCents <= 0 {
            return "You're past the earn-room cliff this month."
        }
        return "You can earn about \(amount) more before your check would drop to zero."
    }

    private func v2AccessibilityLabel(projected: String, v2Status: String) -> String {
        var parts = ["Projected SSI this month: \(projected). Status: \(v2Status)."]
        if let earnRoomCents = income.earnRoomGrossCents {
            parts.append(earnRoomNarrative(earnRoomCents: earnRoomCents))
        }
        if let v2Note = income.v2Note { parts.append(v2Note) }
        return parts.joined(separator: " ")
    }

    /// Derive a chip status from the v2 fields. The legacy
    /// `income.status` compares countable income to the SGA threshold,
    /// which is meaningless once we're FBR-based — so we synthesize a
    /// v2-aware status from earn-room and eligibility.
    private static func deriveV2Status(income: SSIIncome) -> String {
        if income.eligibleForCash == false { return "over" }
        if let earnRoom = income.earnRoomGrossCents, earnRoom < 20_000 {
            return "warning"  // less than $200 of room — near the cliff
        }
        return "safe"
    }

    // MARK: - Legacy — countable income vs SGA threshold (engine off)
    private var legacyBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Countable income this month")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(income.formatted["countable"] ?? "$0.00")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                    Text("threshold \(income.formatted["threshold"] ?? "$0.00")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
                SSIStatusChip(status: income.status)
            }
            SSIProgressBar(
                pctUsed: SSIProgressBar.pctUsed(
                    valueCents: income.countableCents,
                    capCents: income.thresholdCents
                ),
                status: income.status
            )
            Text(income.note)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(18)
        .background(ssiHeroGradient, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(legacyAccessibilityLabel)
    }

    private var legacyAccessibilityLabel: String {
        let countable = income.formatted["countable"] ?? "zero dollars"
        let threshold = income.formatted["threshold"] ?? "zero dollars"
        let status = income.status.replacingOccurrences(of: "_", with: " ")
        return "Countable income this month: \(countable). Threshold: \(threshold). Status: \(status). \(income.note)"
    }
}

private struct SSINextDepositCard: View {
    let next: SSANextDeposit

    var body: some View {
        let amount = BudgetFormatter.cents(next.expectedAmountCents)
        let dateText = BudgetFormatter.friendlyDate(next.expectedDateIso) ?? next.expectedDateIso
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next SSA check")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                if next.confidence != "high" {
                    Text(next.confidence.capitalized)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.18), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            Text("\(amount) expected \(dateText)")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(ssiHeroGradient, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Next social security check: \(amount) expected \(dateText). Confidence \(next.confidence)."
        )
    }
}

private struct SSIOverpaymentBanner: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Possible overpayment: \(reason)")
    }
}

// MARK: - SSI deduction candidates (Phase 3)

/// Surfaced when the backend classifier flagged one or more
/// transactions as possible Blind Work Expenses or Impairment-
/// Related Work Expenses. Each row opens a confirmation sheet that
/// lets the user accept, switch buckets, or dismiss without writing.
private struct SSIDeductionCandidatesCard: View {
    let candidates: [SSIDeductionCandidate]
    let onConfirm: (SSIDeductionCandidate, SSIExclusionType) async -> Void

    @State private var presented: SSIDeductionCandidate?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text("Possible deductions spotted")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Text("Confirm any that were really work-related and we'll subtract them from your countable income this month.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(candidates) { candidate in
                    candidateRow(candidate)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .sheet(item: $presented) { candidate in
            SSIDeductionConfirmView(
                candidate: candidate,
                onConfirm: { type in
                    await onConfirm(candidate, type)
                }
            )
        }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: SSIDeductionCandidate) -> some View {
        Button {
            presented = candidate
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.description.isEmpty ? "Transaction" : candidate.description)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(typeLabel(candidate.suggestedType)) • \(BudgetFormatter.cents(candidate.amountCents))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Possible \(typeLabel(candidate.suggestedType)). \(candidate.description). Amount \(BudgetFormatter.cents(candidate.amountCents)). Tap to review."
        )
        .accessibilityHint("Opens the confirmation sheet.")
    }

    private func typeLabel(_ type: SSIExclusionType) -> String {
        switch type {
        case .bwe: return "Blind Work Expense"
        case .irwe: return "Impairment-Related Work Expense"
        case .burial: return "Burial-fund deposit"
        }
    }
}

// MARK: - Shared SSI pieces

private struct SSIStatusChip: View {
    let status: String

    var body: some View {
        Text(prettyLabel)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipBackground, in: Capsule())
            .foregroundStyle(chipForeground)
    }

    private var prettyLabel: String {
        switch status {
        case "over":     return "Over"
        case "warning":  return "Warning"
        case "safe":     return "Safe"
        default:         return status.capitalized
        }
    }

    private var chipBackground: Color {
        switch status {
        case "over":     return Color(red: 1.00, green: 0.45, blue: 0.35).opacity(0.30)
        case "warning":  return Color(red: 1.00, green: 0.65, blue: 0.25).opacity(0.30)
        case "safe":     return Color(red: 0.40, green: 0.85, blue: 0.55).opacity(0.30)
        default:         return Color.white.opacity(0.20)
        }
    }

    private var chipForeground: Color {
        switch status {
        case "over":     return Color(red: 1.00, green: 0.78, blue: 0.72)
        case "warning":  return Color(red: 1.00, green: 0.86, blue: 0.62)
        case "safe":     return Color(red: 0.74, green: 0.96, blue: 0.81)
        default:         return .white
        }
    }
}

private struct SSIProgressBar: View {
    let pctUsed: Double
    let status: String

    var body: some View {
        GeometryReader { geo in
            let pct = min(max(pctUsed / 100.0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(progressColor)
                    .frame(width: geo.size.width * CGFloat(pct))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true) // announced via parent label
    }

    private var progressColor: Color {
        switch status {
        case "over":     return Color(red: 1.00, green: 0.45, blue: 0.35)
        case "warning":  return Color(red: 1.00, green: 0.65, blue: 0.25)
        case "safe":     return Color(red: 0.40, green: 0.85, blue: 0.55)
        default:         return Color(red: 0.95, green: 0.80, blue: 0.35)
        }
    }

    /// Compute pctUsed for income (which the API doesn't return directly —
    /// resources comes with pct_used pre-baked, income has only the cents
    /// values). Defensive against zero-cap so we don't divide by zero.
    static func pctUsed(valueCents: Int, capCents: Int) -> Double {
        guard capCents > 0 else { return valueCents > 0 ? 100 : 0 }
        return min(Double(valueCents) / Double(capCents) * 100, 9999)
    }
}

// MARK: - Breakdown-by-Category entry row

/// Single card on the main Budget tab that pushes BudgetCategoryListView.
/// Replaces the inline per-category list — keeps the tab scannable for
/// VoiceOver users + sighted users alike.
private struct BreakdownByCategoryRow: View {
    let count: Int
    let hasBudget: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text("Breakdown by Category")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to open the full category breakdown.")
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.22))
                .frame(width: 36, height: 36)
            Image(systemName: "chart.pie.fill")
                .foregroundStyle(Color.blue)
        }
    }

    private var subtitle: String {
        let word = count == 1 ? "category" : "categories"
        if hasBudget {
            return "\(count) \(word) with limits"
        }
        return "\(count) \(word) this month"
    }

    private var accessibilityLabel: String {
        "Breakdown by Category. \(subtitle)."
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
