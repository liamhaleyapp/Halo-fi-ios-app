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
    @State private var showSources = false
    @State private var showingEditor = false
    private var summary: IncomeSummary? { loaded?.month == month ? loaded : (month == CalendarView.currentMonthKey() ? dataManager.incomeSummary : nil) }
    var body: some View {
        List {
            Section {
                HStack {
                    Button("Previous month") { shift(-1) }.frame(minHeight: 44)
                    Spacer()
                    Button("Next month") { shift(1) }.frame(minHeight: 44)
                        .disabled(month >= CalendarView.currentMonthKey())
                }
                Text(month).font(.headline).accessibilityAddTraits(.isHeader)
                if let s = summary {
                    ScreenReaderSummaryHeader(verdict: "Income received", detail: s.totalIncomeCents.map { BudgetFormatter.cents($0) + " identified this month." } ?? "Refreshing income…", tone: .neutral)
                    if let items = s.incomeItems {
                        if items.isEmpty { Text("No income identified this month.") }
                        ForEach(items) { item in
                            NavigationLink { detail(item) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.source).font(.headline)
                                    Text(BudgetFormatter.cents(item.amountCents)).font(.title2.bold())
                                    Text(DepositLabelSheet.spokenDate(item.occurredOn)).font(.subheadline)
                                }.frame(minHeight: 56)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(DepositLabelSheet.spokenDate(item.occurredOn)), \(item.source), \(VoiceOverFormatter.dollars(item.amountCents)).")
                            .accessibilityHint("Opens income details and classification.")
                        }
                    }
                    if userManager.capabilities.expenseType == .bwe, let count = s.paychecksNeedingTaxReview, count > 0 {
                        Text("\(count) paychecks need tax withholding reviewed. Open a paycheck to enter its paystub taxes.").font(.subheadline)
                    }
                    if s.paychecksNeedingGross > 0 {
                        Text("\(s.paychecksNeedingGross) paychecks need gross wages for reporting. Open a paycheck to add its paystub amount.")
                    }
                } else { ProgressView("Loading income…") }
                if let error { Text(error).foregroundStyle(DesignTokens.ToneText.act) }
            }
            Section {
                DisclosureGroup("Manage income sources", isExpanded: $showSources) {
                    ForEach(summary?.sources ?? []) { source in
                        Button { sourceTarget = source } label: {
                            VStack(alignment: .leading) {
                                Text(source.employer ?? source.sourceKey.capitalized).font(.headline)
                                Text(Self.sourceLine(source)).font(.subheadline)
                            }.frame(minHeight: 48)
                        }
                    }
                    Button("Edit planned income and benefits") { showingEditor = true }.frame(minHeight: 44)
                }
            }
        }
        .navigationTitle("Income")
        .task(id: month) { await load() }
        .refreshable { await load() }
        .sheet(item: $sourceTarget, onDismiss: { Task { await load() } }) { IncomeSourceEditorSheet(source: $0) }
        .sheet(item: $grossTarget, onDismiss: { Task { await load() } }) { label in
            DepositLabelSheet(mode: .gross(labelId: label.id, employer: label.employer ?? label.source, netCents: label.netCents, lastGrossCents: label.grossCents, occurredOn: label.occurredOn))
        }
        .sheet(item: $relabelTarget, onDismiss: { Task { await load() } }) { item in
            DepositLabelSheet(mode: .label(transactionId: item.transactionId, source: item.source, amountCents: item.amountCents, occurredOn: item.occurredOn))
        }
        .sheet(isPresented: $showingEditor) { IncomeEditorView() }
    }
    private func detail(_ item: IncomeActivityItem) -> some View {
        List {
            Text(item.source).font(.title2.bold())
            Text(BudgetFormatter.cents(item.amountCents)).font(.largeTitle.bold())
            Text(DepositLabelSheet.spokenDate(item.occurredOn))
            Text((IncomeKind(rawValue: item.kind) ?? .other).title)
            Text(item.classification == "confirmed" ? "Classification confirmed by you." : "Identified from bank data. Review if this looks wrong.")
            Button("Change classification") { relabelTarget = item }.frame(minHeight: 44)
            if let label = summary?.labels.first(where: { $0.transactionId == item.transactionId }), label.kind == "work_income" {
                Text(label.grossCents.map { "Gross wages: " + BudgetFormatter.cents($0) } ?? "Gross wages needed from your paystub.")
                Button("Review gross wages") { grossTarget = label }.frame(minHeight: 44)
                PaystubTaxEditor(label: label) { Task { await load(); await dataManager.refresh() } }
            }
        }.navigationTitle("Income details")
    }
    private func shift(_ delta: Int) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        if let date = f.date(from: month), let moved = Calendar.current.date(byAdding: .month, value: delta, to: date) { month = f.string(from: moved) }
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
        } catch is CancellationError {} catch { self.error = "Could not load income. Pull to retry." }
    }
    static func sourceLine(_ s: IncomeSource) -> String {
        var parts: [String] = [(IncomeKind(rawValue: s.kind) ?? .other).title]
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
}


private struct PaystubTaxEditor: View {
    let label: IncomeLabelView
    let onSaved: () -> Void
    @State private var amount = ""
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tax withholding").font(.headline)
            Text("Enter income tax, Social Security and Medicare taxes from this paystub. Do not include insurance or retirement deductions.").font(.subheadline)
            TextField("Tax withholding in dollars", text: $amount).keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Tax withholding in dollars")
            Button("Confirm tax withholding") {
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
            }.disabled(saving || SpendablePlanEditor.cents(amount) == nil || label.grossCents == nil).frame(minHeight: 44)
            if let message { Text(message).font(.callout) }
        }.onAppear { if let cents = label.taxesCents { amount = String(format: "%.2f", Double(cents)/100) } }
    }
}
