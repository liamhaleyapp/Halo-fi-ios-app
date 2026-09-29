//
//  IncomeView.swift
//  Halo-fi-IOS
//
//  Money → Income (rebuilt 2026-09-29): the month's deposits as the same
//  card rows as Calendar and Bills — kind icon, source, date on the left,
//  the amount on the right — under the one summary header VoiceOver reads
//  first. Sources and planned income sit below, one level deeper.
//

import SwiftUI

struct IncomeView: View {
    @Environment(UserManager.self) private var userManager
    @Environment(BudgetDataManager.self) private var dataManager
    @State private var month = CalendarView.currentMonthKey()
    @State private var loaded: IncomeSummary?
    @State private var error: String?
    @State private var sourceTarget: IncomeSource?
    @State private var grossTarget: IncomeLabelView?
    @State private var relabelTarget: IncomeActivityItem?
    @State private var showingEditor = false
    @AccessibilityFocusState private var focus: Bool

    private var summary: IncomeSummary? { loaded?.month == month ? loaded : (month == CalendarView.currentMonthKey() ? dataManager.incomeSummary : nil) }
    private var isCurrentMonth: Bool { month >= CalendarView.currentMonthKey() }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                monthNav
                if let s = summary {
                    let lines = Self.summaryLines(s, capabilities: userManager.capabilities)
                    ScreenReaderSummaryHeader(verdict: "Income received", detail: ([lines.header] + lines.notes).joined(separator: " "),
                                              tone: lines.notes.isEmpty ? .neutral : .watch, visualDetail: lines.header)
                        .accessibilityFocused($focus)
                    let items = s.incomeItems ?? []
                    if items.isEmpty {
                        Text(isCurrentMonth ? "No income identified yet this month. Deposits show here as they arrive; open one to say what it is."
                                            : "No income identified for \(Self.monthLabel(month)).")
                            .font(.subheadline).foregroundColor(.haloTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).haloCard()
                    }
                    ForEach(items) { item in incomeRow(item) }
                    sourcesSection(s)
                } else if let error {
                    Text(error).font(.callout).foregroundStyle(DesignTokens.ToneText.act)
                    Button("Try again") { Task { await load() } }.buttonStyle(.bordered).frame(minHeight: 44)
                } else {
                    ProgressView("Loading income…")
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.large)
        .task(id: month) { await load() }
        .onAppear { Diagnostics.screen("income") }
        .onChange(of: month) { _, _ in focus = true }
        .refreshable {
            await load()
            UIAccessibility.post(notification: .announcement, argument: "Updated.")
        }
        .sheet(item: $sourceTarget, onDismiss: { Task { await reload() } }) { IncomeSourceEditorSheet(source: $0) }
        .sheet(item: $grossTarget, onDismiss: { Task { await reload() } }) { label in
            DepositLabelSheet(mode: .gross(labelId: label.id, employer: label.employer ?? label.source, netCents: label.netCents, lastGrossCents: label.grossCents, occurredOn: label.occurredOn))
        }
        .sheet(item: $relabelTarget, onDismiss: { Task { await reload() } }) { item in
            DepositLabelSheet(mode: .label(transactionId: item.transactionId, source: item.source, amountCents: item.amountCents, occurredOn: item.occurredOn))
        }
        .sheet(isPresented: $showingEditor, onDismiss: { Task { await reload() } }) { IncomeEditorView() }
    }

    // MARK: - Month

    private var monthNav: some View {
        HStack {
            Button { shift(-1) } label: {
                Label("Previous month", systemImage: "chevron.left").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(Self.monthLabel(month)).font(.haloRowTitle).foregroundColor(.haloTextPrimary).accessibilityHidden(true)
            Spacer()
            Button { shift(1) } label: {
                Label("Next month", systemImage: "chevron.right").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next month")
            .disabled(isCurrentMonth)
        }
    }

    /// "September 2026" from "2026-09".
    static func monthLabel(_ key: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        guard let date = f.date(from: key) else { return key }
        let out = DateFormatter(); out.dateFormat = "MMMM yyyy"
        return out.string(from: date)
    }

    private func shift(_ delta: Int) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        if let date = f.date(from: month), let moved = Calendar.current.date(byAdding: .month, value: delta, to: date) { month = f.string(from: moved) }
    }

    // MARK: - Rows

    private func incomeRow(_ item: IncomeActivityItem) -> some View {
        let kind = IncomeKind(rawValue: item.kind) ?? .other
        let when = TabSummaries.spokenDate(item.occurredOn)
        let state = item.classification == "confirmed" ? "confirmed by you" : "from bank data"
        return NavigationLink { detail(item) } label: {
            HaloRow {
                HaloIconTile(icon: kind.icon, tint: kind == .workIncome ? .haloPositive : .teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.source).font(.haloRowTitle).foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Self.shortKind(kind)) · \(state)").font(.subheadline).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(BudgetFormatter.cents(item.amountCents)).font(.title3.bold()).foregroundColor(DesignTokens.ToneText.positive)
                    Text(when).font(.subheadline).foregroundColor(.haloTextSecondary)
                }
                HaloChevron()
            }
            .padding(14)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
            .haloCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(when), \(item.source), \(VoiceOverFormatter.dollars(item.amountCents)), \(Self.shortKind(kind).lowercased()), \(state).")
        .accessibilityHint("Opens the deposit to change what it is.")
    }

    /// The kind as a short noun for a row ("Work income", "Benefit"), not the
    /// first-person answer used on the question sheet.
    static func shortKind(_ kind: IncomeKind) -> String {
        switch kind {
        case .workIncome: return "Work income"
        case .benefit: return "Benefit"
        case .transfer: return "Transfer"
        case .refund: return "Refund"
        case .gift: return "Gift"
        case .other: return "Other"
        case .unsure: return "Not sure yet"
        }
    }

    // MARK: - Sources

    private func sourcesSection(_ s: IncomeSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where it comes from")
                .font(.subheadline.weight(.semibold)).foregroundColor(.haloTextSecondary)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            if s.sources.isEmpty {
                Text("HaloFi learns a source the first time you say what a deposit is.")
                    .font(.subheadline).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).haloCard()
            }
            ForEach(s.sources) { source in sourceRow(source) }
            Button { showingEditor = true } label: {
                HaloRow {
                    HaloIconTile(icon: "calendar.badge.clock", tint: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Planned income and benefits").font(.haloRowTitle).foregroundColor(.haloTextPrimary)
                        Text("What you expect each month, for the budget.").font(.subheadline).foregroundColor(.haloTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    HaloChevron()
                }
                .padding(14).frame(minHeight: 64).contentShape(Rectangle()).haloCard()
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Planned income and benefits. What you expect each month, for the budget.")
            .accessibilityHint("Opens the planned income editor.")
        }
    }

    private func sourceRow(_ source: IncomeSource) -> some View {
        let kind = IncomeKind(rawValue: source.kind) ?? .other
        let name = source.employer ?? source.sourceKey.capitalized
        let line = Self.sourceLine(source)
        return Button { sourceTarget = source } label: {
            HaloRow {
                HaloIconTile(icon: kind.icon, tint: kind == .workIncome ? .haloPositive : .teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.haloRowTitle).foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line).font(.subheadline).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HaloChevron()
            }
            .padding(14).frame(minHeight: 64).contentShape(Rectangle()).haloCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(line).")
        .accessibilityHint("Opens this source to change its kind or employer.")
    }

    // MARK: - Detail

    private func detail(_ item: IncomeActivityItem) -> some View {
        let kind = IncomeKind(rawValue: item.kind) ?? .other
        let confirmed = item.classification == "confirmed"
        let label = summary?.labels.first(where: { $0.transactionId == item.transactionId })
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.source).font(.haloTitle).foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(BudgetFormatter.cents(item.amountCents)).font(.haloDisplay(40)).foregroundColor(DesignTokens.ToneText.positive)
                    Text("Arrived \(TabSummaries.spokenDate(item.occurredOn)).").font(.body).foregroundColor(.haloTextSecondary)
                    Text(Self.shortKind(kind) + (confirmed ? ", confirmed by you." : ", identified from bank data. Change it if that's wrong."))
                        .font(.subheadline).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).haloCard()
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("\(item.source), \(VoiceOverFormatter.dollars(item.amountCents)), arrived \(TabSummaries.spokenDate(item.occurredOn)). \(Self.shortKind(kind))" + (confirmed ? ", confirmed by you." : ", identified from bank data."))

                Button { relabelTarget = item } label: {
                    Label("Change what this is", systemImage: "tag.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Asks again whether this is work income, a benefit, a transfer, a refund or a gift.")

                // Gross wages and paystub taxes are for the SSA report; nothing to ask a non-benefit user.
                if userManager.capabilities.showsBenefitsLane, let label, label.kind == "work_income" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("For your Social Security report")
                            .font(.subheadline.weight(.semibold)).foregroundColor(.haloTextSecondary)
                            .accessibilityAddTraits(.isHeader)
                        Text(label.grossCents.map { "Gross wages: " + BudgetFormatter.cents($0) } ?? "Gross wages needed from your paystub.")
                            .font(.body).foregroundColor(.haloTextPrimary)
                        Button { grossTarget = label } label: {
                            Label(label.grossCents == nil ? "Add gross wages" : "Review gross wages", systemImage: "doc.text.fill")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.bordered)
                        PaystubTaxEditor(label: label) { Task { await reload() } }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).haloCard()
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Income details")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Words

    /// The header line and the notes under it. Benefit-only wording
    /// (gross wages, paystub taxes) stays off a non-benefit user's screen.
    static func summaryLines(_ s: IncomeSummary, capabilities: UserCapabilities) -> (header: String, notes: [String]) {
        let count = s.incomeItems?.count ?? 0
        let header: String
        if let total = s.totalIncomeCents {
            header = count == 0 ? "Nothing identified yet."
                : "\(BudgetFormatter.cents(total)) from \(VoiceOverFormatter.count(count, singular: "deposit", plural: "deposits"))."
        } else {
            header = "Refreshing income…"
        }
        var notes: [String] = []
        if capabilities.expenseType == .bwe, let count = s.paychecksNeedingTaxReview, count > 0 {
            notes.append("\(count) paychecks need tax withholding reviewed. Open a paycheck to enter its paystub taxes.")
        }
        if capabilities.showsBenefitsLane, s.paychecksNeedingGross > 0 {
            notes.append("\(s.paychecksNeedingGross) paychecks need gross wages for reporting. Open a paycheck to add its paystub amount.")
        }
        return (header, notes)
    }

    static func sourceLine(_ s: IncomeSource) -> String {
        var parts: [String] = [shortKind(IncomeKind(rawValue: s.kind) ?? .other)]
        if let cadence = s.cadenceDays {
            switch cadence {
            case 7: parts.append("every week")
            case 14: parts.append("every 2 weeks")
            case 15: parts.append("twice a month")
            case 30, 31: parts.append("monthly")
            default: parts.append("about every \(cadence) days")
            }
        }
        if let g = s.lastGrossCents { parts.append("last gross \(BudgetFormatter.cents(g))") }
        else if let n = s.lastNetCents { parts.append("last \(BudgetFormatter.cents(n))") }
        return parts.joined(separator: " · ")
    }

    /// After any save: this month's list and the Money tab's figures together.
    private func reload() async {
        await load()
        await dataManager.refresh()
    }

    private func load() async {
        if UITestArchetype.isActive { return }
        let requested = month
        let generation = SessionLifetime.shared.current
        do {
            let result = try await IncomeService.shared.summary(month: requested)
            try SessionLifetime.shared.check(generation)
            guard !Task.isCancelled, month == requested else { return }
            loaded = result; error = nil
        } catch is CancellationError {} catch { self.error = "Couldn't load income. Pull down to try again." }
    }
}


private struct PaystubTaxEditor: View {
    let label: IncomeLabelView
    let onSaved: () -> Void
    @State private var amount = ""
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tax withholding").font(.headline).foregroundColor(.haloTextPrimary)
            Text("Enter income tax, Social Security and Medicare taxes from this paystub. Do not include insurance or retirement deductions.")
                .font(.subheadline).foregroundColor(.haloTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Tax withholding in dollars", text: $amount).keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Tax withholding in dollars")
                .accessibilityValue(SpendablePlanEditor.cents(amount).map(VoiceOverFormatter.dollarsAndCents) ?? "")
            Button {
                guard let cents = SpendablePlanEditor.cents(amount) else { return }
                saving = true
                Task {
                    do {
                        _ = try await IncomeService.shared.confirmTaxes(id: label.id, taxesCents: cents)
                        message = "Tax withholding saved. Attach the paystub to the work-expense entry if applicable."
                        onSaved()
                    } catch { message = error.localizedDescription }
                    saving = false
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
            } label: {
                Text("Confirm tax withholding").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
            .disabled(saving || SpendablePlanEditor.cents(amount) == nil || label.grossCents == nil)
            if let message { Text(message).font(.callout).foregroundColor(.haloTextSecondary).fixedSize(horizontal: false, vertical: true) }
        }.onAppear { if let cents = label.taxesCents { amount = String(format: "%.2f", Double(cents)/100) } }
    }
}
