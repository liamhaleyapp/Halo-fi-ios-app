//
//  BillsView.swift
//  Halo-fi-IOS
//
//  Money → Bills (2026-09-05): the recurring charges Plaid sees, with the
//  user's yes / no. Confirmed bills feed the projection to the 1st.
//

import SwiftUI

struct BillsView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @State private var target: RecurringStream?
    @State private var loaded = false

    private var bills: RecurringResponse? { dataManager.bills }
    private var confirmed: [RecurringStream] { bills?.streams.filter { $0.userConfirmed == true } ?? [] }
    private var unanswered: [RecurringStream] { bills?.streams.filter { $0.userConfirmed == nil } ?? [] }
    private var declined: [RecurringStream] { bills?.streams.filter { $0.userConfirmed == false } ?? [] }

    var body: some View {
        List {
            Section {
                header.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            if !unanswered.isEmpty {
                Section {
                    ForEach(unanswered) { s in row(s, prompt: true) }
                } header: { Text("Is this a bill?") } footer: { Text("Tap one to answer. Bills count in what is left by the 1st.") }
            }
            Section {
                if confirmed.isEmpty {
                    Text(loaded ? "No bills confirmed yet." : "Loading…").foregroundColor(.haloTextSecondary)
                } else {
                    ForEach(confirmed) { s in row(s, prompt: false) }
                }
            } header: { Text("Your bills") }
            if !declined.isEmpty {
                Section {
                    ForEach(declined) { s in row(s, prompt: false) }
                } header: { Text("Not bills") } footer: { Text("Tap to change an answer.") }
            }
            Section {
                Text("Estimate for education only — Social Security makes all actual decisions.")
                    .font(.caption).foregroundColor(.haloTextSecondary)
            }
        }
        .navigationTitle("Bills")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await dataManager.refresh() }
        .task {
            if dataManager.bills == nil { await dataManager.refresh() }
            loaded = true
        }
        .sheet(item: $target) { s in
            BillConfirmSheet(streamId: s.streamId, merchant: s.merchant, amountCents: s.averageCents,
                             frequencyLabel: s.frequencyLabel, nextExpected: s.nextExpected)
        }
    }

    private var header: some View {
        let count = confirmed.count
        let monthly = bills?.monthlyBillsCents ?? 0
        let next = confirmed.compactMap { s in s.nextExpected.map { ($0, s) } }.min { $0.0 < $1.0 }
        var detail = count == 0 ? "Nothing confirmed yet." : "\(VoiceOverFormatter.count(count, singular: "bill", plural: "bills")), about \(VoiceOverFormatter.dollars(monthly)) a month."
        if let next { detail += " Next: \(next.1.merchant), \(TabSummaries.spokenDate(next.0))." }
        if !unanswered.isEmpty { detail += " \(VoiceOverFormatter.count(unanswered.count, singular: "charge", plural: "charges")) waiting for a yes or no." }
        return ScreenReaderSummaryHeader(verdict: "Bills", detail: detail, isEstimate: count > 0, tone: unanswered.isEmpty ? .neutral : .watch)
    }

    private func row(_ s: RecurringStream, prompt: Bool) -> some View {
        Button { target = s } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.merchant).font(.body.weight(.semibold)).foregroundColor(.haloTextPrimary).lineLimit(1)
                    Text("\(BudgetFormatter.cents(s.averageCents)) \(s.frequencyLabel)" + (s.nextExpected.map { " · next \(TabSummaries.spokenDate($0))" } ?? ""))
                        .font(.caption).foregroundColor(.haloTextSecondary)
                }
                Spacer()
                Image(systemName: prompt ? "questionmark.circle" : (s.userConfirmed == true ? "checkmark.circle.fill" : "xmark.circle"))
                    .foregroundColor(prompt ? .orange : (s.userConfirmed == true ? .haloPositive : .haloTextTertiary))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.merchant), \(VoiceOverFormatter.dollars(s.averageCents)) \(s.frequencyLabel)" + (s.nextExpected.map { ", next \(TabSummaries.spokenDate($0))" } ?? "") + (prompt ? ". Not answered." : (s.userConfirmed == true ? ". Counted as a bill." : ". Not a bill.")))
        .accessibilityHint(prompt ? "Asks whether this is a bill." : "Changes the answer.")
        .accessibilityAddTraits(.isButton)
    }
}
