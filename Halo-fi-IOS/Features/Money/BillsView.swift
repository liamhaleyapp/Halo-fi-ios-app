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
    @Environment(UserManager.self) private var userManager
    @State private var target: RecurringStream?
    @State private var loaded = false
    @State private var showHistory = false

    private var bills: RecurringResponse? { dataManager.bills }
    private var streams: [RecurringStream] { bills?.dedupedStreams ?? [] }
    private var confirmed: [RecurringStream] { streams.filter { $0.userConfirmed == true && $0.forecastStatus != "cancelled" && $0.forecastStatus != "interrupted" } }
    private var confirmedBills: [RecurringStream] { confirmed.filter { !$0.isSubscription } }
    private var confirmedSubscriptions: [RecurringStream] { confirmed.filter { $0.isSubscription } }
    private var unanswered: [RecurringStream] { streams.filter { $0.userConfirmed == nil && $0.forecastStatus != "cancelled" && $0.forecastStatus != "interrupted" } }
    private var declined: [RecurringStream] { streams.filter { $0.userConfirmed == false || $0.forecastStatus == "cancelled" || $0.forecastStatus == "interrupted" } }
    private var statementPayments: [StatementPayment] { bills?.statementPayments ?? [] }

    var body: some View {
        List {
            Section {
                header.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            if !statementPayments.isEmpty {
                Section {
                    ForEach(statementPayments) { p in statementRow(p) }
                } header: { Text("From your statements") } footer: { Text("Card and loan payments with the exact due date and minimum your bank reported.") }
            }
            if !unanswered.isEmpty {
                Section {
                    ForEach(unanswered) { s in row(s, prompt: true) }
                } header: { Text("Waiting for your answer") } footer: { Text("Tap one to say bill, subscription, or neither. Answers are remembered for that payee on every account.") }
            }
            Section {
                if confirmedBills.isEmpty {
                    Text(loaded ? "No bills yet." : "Loading…").foregroundColor(.haloTextSecondary)
                } else {
                    ForEach(confirmedBills) { s in row(s, prompt: false) }
                }
            } header: { Text("Bills") } footer: { Text("Rent, utilities, phone, insurance, loan payments.") }
            Section {
                if confirmedSubscriptions.isEmpty {
                    Text(loaded ? "No subscriptions yet." : "Loading…").foregroundColor(.haloTextSecondary)
                } else {
                    ForEach(confirmedSubscriptions) { s in row(s, prompt: false) }
                }
            } header: { Text("Subscriptions") } footer: { Text("Streaming, software, memberships. Tap one to change its kind.") }
            if !declined.isEmpty {
                Section {
                    DisclosureGroup("Review hidden or stopped payments", isExpanded: $showHistory) {
                        ForEach(declined) { s in row(s, prompt: false) }
                    }
                } header: { Text("History") } footer: { Text("Tap to change an answer.") }
            }
            Section {
                Text("Expected payments are based on recorded activity. Open an item to review its last charge or record a cancellation.")
                    .font(.caption).foregroundColor(.haloTextSecondary)
            }
        }
        .navigationTitle("Bills")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await dataManager.refresh()
            UIAccessibility.post(notification: .announcement, argument: "Updated.")
        }
        .onAppear { Diagnostics.screen("bills") }
        .task {
            if dataManager.bills == nil { await dataManager.refresh() }
            loaded = true
        }
        .sheet(item: $target) { s in
            BillConfirmSheet(streamId: s.streamId, merchant: s.merchant, amountCents: s.displayCents,
                             frequencyLabel: s.frequencyLabel, nextExpected: s.nextExpected,
                             suggestedKind: s.kind ?? "bill", amountVaries: s.amountVaries ?? false)
        }
    }

    private var header: some View {
        let count = confirmed.count
        let monthly = bills?.monthlyBillsCents ?? 0
        let next = confirmed.compactMap { s in s.nextExpected.map { ($0, s) } }.min { $0.0 < $1.0 }
        var detail = count == 0
            ? "Nothing confirmed yet."
            : "\(VoiceOverFormatter.count(confirmedBills.count, singular: "bill", plural: "bills")) and \(VoiceOverFormatter.count(confirmedSubscriptions.count, singular: "subscription", plural: "subscriptions")), about \(VoiceOverFormatter.dollars(monthly)) a month."
        if let next { detail += " Next: \(next.1.merchant), \(TabSummaries.spokenDate(next.0))." }
        if !unanswered.isEmpty { detail += " \(VoiceOverFormatter.count(unanswered.count, singular: "charge", plural: "charges")) waiting for a yes or no." }
        return ScreenReaderSummaryHeader(verdict: "Bills and subscriptions", detail: detail,
                                         isEstimate: Self.headerIsEstimate(confirmedCount: count, capabilities: userManager.capabilities),
                                         tone: unanswered.isEmpty ? .neutral : .watch)
    }

    /// The Social Security disclaimer only means something to benefit users,
    /// and only once a confirmed number is on screen.
    static func headerIsEstimate(confirmedCount: Int, capabilities: UserCapabilities) -> Bool {
        confirmedCount > 0 && capabilities.showsBenefitsLane
    }

    private func statementRow(_ p: StatementPayment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.label).font(.body.weight(.semibold)).foregroundColor(.haloTextPrimary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(p.line).font(.caption).foregroundColor(p.isOverdue ? DesignTokens.ToneText.act : .haloTextSecondary)
            }
            Spacer()
            Image(systemName: p.isOverdue ? "exclamationmark.circle.fill" : "creditcard.fill")
                .foregroundColor(p.isOverdue ? .red : .haloTextSecondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(p.label). \(p.line)")
    }

    /// Unanswered rows say what was seen, not what to expect: no cadence
    /// or next-date claim until the user says it is a bill.
    private func secondLine(_ s: RecurringStream, prompt: Bool) -> String {
        let varies = (s.amountVaries ?? false) ? ", varies" : ""
        if prompt { return "Seen \(s.frequencyLabel)\(varies)" }
        return "\(s.frequencyLabel)\(varies) · \(s.forecastLine)"
    }

    /// Only when the amount moved or a lump sum was left out.
    private func thirdLine(_ s: RecurringStream) -> String? {
        if let change = s.amountChanged { return "Was \(BudgetFormatter.cents(change.fromCents))" }
        if let extra = s.extraPayments?.first { return "+ extra payment \(TabSummaries.spokenDate(extra.date))" }
        return nil
    }

    private func row(_ s: RecurringStream, prompt: Bool) -> some View {
        let second = secondLine(s, prompt: prompt)
        let third = thirdLine(s)
        let answer = prompt ? "Not answered." : (s.userConfirmed == true ? "Counted as a \(s.kindWord)." : "Not a bill or subscription.")
        return Button { target = s } label: {
            HaloRow {
                logo(s)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.merchant).font(.haloRowTitle).foregroundColor(.haloTextPrimary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(second).font(.subheadline).foregroundColor(.haloTextSecondary).fixedSize(horizontal: false, vertical: true)
                    if let third { Text(third).font(.subheadline).foregroundColor(.haloTextSecondary) }
                }
                Spacer(minLength: 0)
                Text(s.amountText).font(.title3.bold()).foregroundColor(.haloTextPrimary)
                Image(systemName: prompt ? "questionmark.circle" : (s.userConfirmed == true ? "checkmark.circle.fill" : "xmark.circle"))
                    .foregroundColor(prompt ? .orange : (s.userConfirmed == true ? .haloPositive : .haloTextSecondary))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.merchant), \(s.spokenAmount), \(second)." + (third.map { " \($0)." } ?? "") + " \(answer)")
        .accessibilityHint(prompt ? "Asks whether this is a bill, a subscription, or neither." : "Changes the answer.")
        .accessibilityAddTraits(.isButton)
    }

    /// Merchant logo when the server has one, else the kind's icon. Decorative.
    @ViewBuilder
    private func logo(_ s: RecurringStream) -> some View {
        let tile = HaloIconTile(icon: s.isSubscription ? "repeat.circle.fill" : "doc.text.fill", tint: s.isSubscription ? .indigo : .teal)
        if let logoUrl = s.logoUrl, let url = URL(string: logoUrl) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: { tile }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .accessibilityHidden(true)
        } else {
            tile.accessibilityHidden(true)
        }
    }
}
