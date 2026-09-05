//
//  IncomeView.swift
//  Halo-fi-IOS
//
//  Money → Income (Liam, 2026-09-05): what HaloFi has learned about the
//  user's money in — payers and their cadence, this month's work income
//  gross and net, paychecks still missing a gross, the deposits labeled so
//  far — plus the self-reported paycheck and benefit amounts.
//

import SwiftUI

struct IncomeView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(UserManager.self) private var userManager

    @State private var grossTarget: IncomeLabelView?
    @State private var sourceTarget: IncomeSource?
    @State private var forgetTarget: IncomeLabelView?
    @State private var relabelTarget: IncomeLabelView?
    @State private var showingEditor = false
    @State private var summaryLoaded = false

    private var summary: IncomeSummary? { dataManager.incomeSummary }

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if let s = summary, !s.labels.filter({ $0.needsGross }).isEmpty {
                Section {
                    ForEach(s.labels.filter { $0.needsGross }) { label in
                        Button { grossTarget = label } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Paycheck from \(label.employer ?? label.source)").font(.body.weight(.semibold)).foregroundColor(.haloTextPrimary)
                                    Text("\(DepositLabelSheet.spokenDate(label.occurredOn)), \(BudgetFormatter.cents(label.netCents)) after taxes").font(.caption).foregroundColor(.haloTextSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(.haloTextTertiary).accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Asks for the gross on the paystub.")
                    }
                } header: {
                    Text("Paystub gross still needed")
                }
            }

            Section {
                if let s = summary, !s.sources.isEmpty {
                    ForEach(s.sources) { source in
                        Button { sourceTarget = source } label: {
                            HStack {
                                Image(systemName: (IncomeKind(rawValue: source.kind) ?? .other).icon)
                                    .foregroundColor(.indigo).frame(width: 28).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.employer ?? source.sourceKey.capitalized).font(.body.weight(.semibold)).foregroundColor(.haloTextPrimary)
                                    Text(Self.sourceLine(source)).font(.caption).foregroundColor(.haloTextSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundColor(.haloTextTertiary).accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(source.employer ?? source.sourceKey.capitalized). \(Self.sourceLine(source))")
                        .accessibilityHint("Edits this payer: what it is, how often it pays, expected gross and take-home.")
                        .accessibilityAddTraits(.isButton)
                    }
                } else {
                    Text(summaryLoaded
                         ? "Nothing learned yet. When a deposit arrives, the Money tab asks what it was, once per payer."
                         : "Loading…")
                        .foregroundColor(.haloTextSecondary)
                }
            } header: {
                Text("Payers HaloFi remembers")
            } footer: {
                Text("One row per payer, learned from the deposits you answered about. Tap a payer to set how often it pays and what to expect; that becomes your budget's income. \"I'm not sure\" answers are not remembered. Nothing here is sent to Social Security.")
            }

            if let s = summary, !s.labels.isEmpty {
                Section {
                    ForEach(s.labels.sorted { $0.occurredOn > $1.occurredOn }) { label in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label.source).font(.body).foregroundColor(.haloTextPrimary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                Text("\(DepositLabelSheet.spokenDate(label.occurredOn)) · \((IncomeKind(rawValue: label.kind) ?? .other).title)\(label.grossCents.map { " · gross \(BudgetFormatter.cents($0))" } ?? "")")
                                    .font(.caption).foregroundColor(.haloTextSecondary)
                            }
                            Spacer()
                            Text(BudgetFormatter.cents(label.netCents)).font(.body.weight(.semibold))
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .onTapGesture { if label.kind == "unsure" { relabelTarget = label } }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(label.kind == "unsure" ? "Double tap to answer what this deposit was." : "")
                        .accessibilityAddTraits(label.kind == "unsure" ? .isButton : [])
                        .accessibilityAction(named: "Forget this label") { forgetTarget = label }
                        .swipeActions {
                            Button(role: .destructive) { forgetTarget = label } label: { Label("Forget", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text("Deposits this month")
                } footer: {
                    Text("Each deposit you answered about this month, with your answer. Tap an \"I'm not sure\" deposit to answer it now.")
                }
            }

            Section {
                Button { showingEditor = true } label: {
                    Label("Benefit amounts and other fields", systemImage: "pencil")
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Opens the benefit amounts editor.")
            } footer: {
                Text("Estimate for education only — Social Security makes all actual decisions.")
            }
        }
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await dataManager.refresh()
            UIAccessibility.post(notification: .announcement, argument: "Updated.")
        }
        .task {
            if dataManager.incomeSummary == nil { await dataManager.refresh() }
            summaryLoaded = true
        }
        .sheet(item: $grossTarget) { label in
            DepositLabelSheet(mode: .gross(labelId: label.id, employer: label.employer ?? label.source, netCents: label.netCents,
                                           lastGrossCents: summary?.sources.first { $0.sourceKey == label.sourceKey }?.lastGrossCents,
                                           occurredOn: label.occurredOn))
        }
        .sheet(isPresented: $showingEditor) { IncomeEditorView() }
        .sheet(item: $relabelTarget) { label in
            DepositLabelSheet(mode: .label(transactionId: label.transactionId, source: label.source,
                                           amountCents: label.netCents, occurredOn: label.occurredOn))
        }
        .confirmationDialog("Forget this label?", isPresented: Binding(get: { forgetTarget != nil }, set: { if !$0 { forgetTarget = nil } }), titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                guard let label = forgetTarget else { return }
                forgetTarget = nil
                Task {
                    do {
                        try await dataManager.forgetLabel(id: label.id)
                        UIAccessibility.post(notification: .announcement, argument: "Forgotten. \(label.source) will be asked about again.")
                    } catch {
                        UIAccessibility.post(notification: .announcement, argument: "Couldn't forget it. \(error.localizedDescription)")
                    }
                }
            }
            Button("Keep", role: .cancel) { forgetTarget = nil }
        } message: {
            Text("The deposit goes back to unlabeled and any taxes-withheld expense from it is removed.")
        }
        .sheet(item: $sourceTarget) { source in IncomeSourceEditorSheet(source: source) }
    }

    private var header: some View {
        let s = summary
        let gross = s?.workIncomeGrossCents ?? 0
        let line: String = {
            guard let s, !s.workIncome.isEmpty else {
                return "No work income labeled this month yet."
            }
            let employers = s.workIncome.map(\.employer).joined(separator: ", ")
            var text = "Work income this month: \(BudgetFormatter.cents(gross)) gross from \(employers)"
            if s.paychecksNeedingGross > 0 {
                text += ", \(VoiceOverFormatter.count(s.paychecksNeedingGross, singular: "paycheck", plural: "paychecks")) still counted at net"
            }
            return text + "."
        }()
        return ScreenReaderSummaryHeader(
            verdict: gross > 0 ? "Income" : "Income, nothing labeled yet",
            detail: line + (s?.benefitCents ?? 0 > 0 ? " Benefit deposits: \(BudgetFormatter.cents(s!.benefitCents))." : ""),
            isEstimate: (s?.paychecksNeedingGross ?? 0) > 0,
            tone: .neutral
        )
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
