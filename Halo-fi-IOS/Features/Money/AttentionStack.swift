//
//  AttentionStack.swift
//  Halo-fi-IOS
//
//  "Needs your attention": the Money tab shows ONE row; this screen lists
//  every card, most urgent first, each one VoiceOver element and one tap
//  (Liam, 2026-09-05: main screens stay concise, detail is one tap deeper).
//  Deadlines (resources, package, receipts, a bank to reconnect) navigate;
//  learning questions (a deposit, a paycheck's gross, a likely work
//  expense) open a one-question sheet. "Not now" hides a card for a week.
//  Words carry the state, never color alone.
//

import SwiftUI

/// Deadlines remain alerts. Questions are grouped without dropping or limiting them.
struct AttentionSections {
    struct Group: Identifiable {
        let id: String
        let title: String
        let cards: [AttentionCard]
    }
    let alerts: [AttentionCard]
    let groups: [Group]
    init(cards: [AttentionCard]) {
        let filingMonths = Set(cards.filter { $0.kind == "submit_package" }.compactMap { $0.payload.month })
        var alerts: [AttentionCard] = []
        var bills: [AttentionCard] = []
        var income: [AttentionCard] = []
        for card in cards {
            let month = card.payload.month ?? card.payload.occurredOn.map { String($0.prefix(7)) }
            let filingNeedsGross = card.kind == "wage_gross" && (month == nil || filingMonths.contains(month!))
            if card.kind == "bill_confirm" { bills.append(card) }
            else if (card.kind == "deposit_label" || card.kind == "wage_gross") && !filingNeedsGross { income.append(card) }
            else { alerts.append(card) }
        }
        self.alerts = alerts
        self.groups = [Group(id: "bills", title: "Review bills and subscriptions", cards: bills),
                       Group(id: "income", title: "Review income", cards: income)].filter { !$0.cards.isEmpty }
    }
}

struct AttentionView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    let onOpen: (AttentionCard) -> Void
    @State private var reminderCard: AttentionCard?
    @State private var detailCard: AttentionCard?
    @State private var showingDetail = false

    private var cards: [AttentionCard] { dataManager.attentionCards + dataManager.attentionQueue }

    private var sections: AttentionSections { AttentionSections(cards: cards) }

    private var tone: ScreenReaderSummaryHeader.Tone {
        switch sections.alerts.first?.tone {
        case "act": return .act
        case "watch": return .watch
        case .some: return .neutral
        case .none: return .positive
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ScreenReaderSummaryHeader(
                    verdict: sections.alerts.isEmpty
                        ? "No urgent alerts"
                        : VoiceOverFormatter.count(sections.alerts.count, singular: "alert needs you", plural: "alerts need you"),
                    detail: cards.isEmpty
                        ? "New deposits, charges and deadlines show up here as they arrive."
                        : "Alerts first. Review questions below help Halo understand your finances.",
                    tone: tone
                )
                ForEach(sections.alerts) { card in
                    AttentionCardView(card: card, onOpen: {
                        if card.kind == "unlinked_card" { detailCard = card; showingDetail = true }
                        else { onOpen(card) }
                    }, onNotNow: { reminderCard = card })
                }
                if !sections.groups.isEmpty {
                    Text("Help Halo understand your finances")
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(sections.groups) { group in
                        NavigationLink {
                            AttentionReviewView(groupId: group.id, title: group.title, onOpen: onOpen)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.title).font(.headline)
                                Text(VoiceOverFormatter.count(group.cards.count, singular: "question", plural: "questions"))
                            }
                            .foregroundStyle(Color.haloTextPrimary)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                            .padding(16).haloCard()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("attentionGroup-\(group.id)")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 100)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .sheet(item: $reminderCard) { card in
            AttentionReminderSheet(card: card)
        }
        .navigationDestination(isPresented: $showingDetail) {
            if let card = detailCard {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(card.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        Text(card.line)
                        Button("Link another account") { onOpen(card) }.frame(minHeight: 44)
                        AttentionDetailReminder(card: card)
                    }.padding(20).readableContentWidth()
                }.navigationTitle("Cards HaloFi can't see").navigationBarTitleDisplayMode(.inline)
            }
        }
        .navigationTitle("Needs your attention")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await dataManager.refresh()
            UIAccessibility.post(notification: .announcement, argument: cards.isEmpty ? "Updated. Nothing needs you." : "Updated. \(VoiceOverFormatter.count(cards.count, singular: "thing needs you", plural: "things need you")).")
        }
    }
}

struct AttentionStack: View {
    let cards: [AttentionCard]
    let moreCount: Int
    var isRefreshing: Bool = false
    let onOpen: (AttentionCard) -> Void
    let onNotNow: (AttentionCard) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Needs your attention")
                .font(.headline)
                .foregroundColor(.haloTextSecondary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(cards.isEmpty ? "Needs your attention. Nothing right now." : "Needs your attention. \(VoiceOverFormatter.count(cards.count, singular: "item", plural: "items")).")
            if cards.isEmpty {
                Text(isRefreshing ? "Checking…" : "Nothing needs you right now.")
                    .font(.subheadline)
                    .foregroundColor(.haloTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.haloSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("attentionEmpty")
            }
            ForEach(cards) { card in
                AttentionCardView(card: card, onOpen: { onOpen(card) }, onNotNow: { onNotNow(card) })
            }
            if moreCount > 0 {
                Text("\(VoiceOverFormatter.count(moreCount, singular: "more item", plural: "more items")) after these.")
                    .font(.caption)
                    .foregroundColor(.haloTextTertiary)
            }
        }
    }
}

struct AttentionCardView: View {
    let card: AttentionCard
    let onOpen: () -> Void
    let onNotNow: () -> Void

    private var tone: ScreenReaderSummaryHeader.Tone {
        switch card.tone {
        case "act": return .act
        case "watch": return .watch
        default: return .neutral
        }
    }

    private var tint: Color {
        switch card.tone {
        case "act": return .haloNegative
        case "watch": return .orange
        case "learn": return .indigo
        default: return .blue
        }
    }

    private var icon: String {
        switch card.kind {
        case "resources": return "gauge.with.dots.needle.67percent"
        case "submit_package": return "doc.text.fill"
        case "month_end_review": return "checklist"
        case "receipts_needed": return "doc.viewfinder"
        case "bank_reconnect": return "exclamationmark.arrow.triangle.2.circlepath"
        case "deposit_label": return "arrow.down.circle.fill"
        case "wage_gross": return "dollarsign.circle.fill"
        case "work_expense_candidate": return "briefcase.fill"
        case "bill_confirm": return "calendar.badge.clock"
        case "budget_suggestion": return "sparkles"
        case "budget_over": return "chart.pie.fill"
        case "profile_incomplete", "money_profile_incomplete": return "person.text.rectangle.fill"
        case "unlinked_card": return "creditcard.trianglebadge.exclamationmark"
        case "card_overdue": return "exclamationmark.circle.fill"
        default: return "bell.fill"
        }
    }

    private var hint: String {
        switch card.actionType {
        case "label_deposit": return "Opens one question: what this deposit was."
        case "enter_gross": return "Opens one question: the gross on the paystub."
        case "confirm_candidate": return "Opens the confirmation with the type already picked."
        case "open_resource_monitor": return "Opens the resource monitor."
        case "open_package": return "Opens the monthly package."
        case "open_review": return "Opens the month-end review."
        case "open_work_expenses": return "Opens work expenses."
        case "open_accounts": return "Opens your accounts."
        case "confirm_bill": return "Opens one question: is this a bill."
        case "apply_budget_suggestion": return "Shows the proposed limits. One tap to use them, or keep what you have."
        case "open_budget": return "Opens your budget."
        case "open_benefits_profile": return "Opens your benefits profile to answer the rest."
        case "open_money_profile": return "Opens the four setup questions."
        case "open_link_bank": return "Opens the bank link chooser to add those cards."
        default: return "Opens it."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
        Button(action: onOpen) {
            HaloRow {
                HaloIconTile(icon: icon, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title).font(.haloRowTitle).foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.line).font(.subheadline).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HaloChevron()
            }
            .padding(16)
            .frame(minHeight: 72)
            .haloCard(tint: card.learn ? nil : tint)
        }
        .buttonStyle(HapticPlainButtonStyle())
        .contextMenu {
            Button { onNotNow() } label: { Label("Remind me later", systemImage: "clock") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.title). \(card.line)")
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Remind me later") { onNotNow() }
        .accessibilityIdentifier("attentionCard-\(card.kind)")

        }
    }
}

/// A normal sheet, with every action in reading order. No swipe or long-press
/// gesture is required, and a failed save never announces a false dismissal.
struct AttentionReminderSheet: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    let card: AttentionCard
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(card.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Hide this reminder for a while. It returns only if it still needs attention.")
                    delayButton("Remind me in 1 week", days: 7)
                    delayButton("Remind me in 30 days", days: 30)
                    delayButton("Remind me in 90 days", days: 90)
                    if let errorMessage { Text(errorMessage).foregroundStyle(Color.haloNegative) }
                }
                .padding(20)
                .readableContentWidth()
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                CloseToolbarButton(label: "Close", hint: "Closes without changing this reminder.") { dismiss() }.disabled(isSaving)
            } }
            .accessibilityAction(.escape) { if !isSaving { dismiss() } }
            .navigationTitle("Remind me later")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func delayButton(_ title: String, days: Int) -> some View {
        Button {
            isSaving = true
            Task {
                if await dataManager.dismissCard(card, days: days) {
                    UIAccessibility.post(notification: .announcement, argument: "Reminder hidden for \(days) days.")
                    dismiss()
                } else {
                    errorMessage = "Couldn't save that reminder. Please try again."
                    UIAccessibility.post(notification: .announcement, argument: errorMessage)
                }
                isSaving = false
            }
        } label: {
            Text(title).foregroundStyle(Color.haloTextPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(isSaving)
    }
}

private struct AttentionReviewView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    let groupId: String
    let title: String
    let onOpen: (AttentionCard) -> Void
    @State private var reminderCard: AttentionCard?
    private var cards: [AttentionCard] {
        AttentionSections(cards: dataManager.attentionCards + dataManager.attentionQueue)
            .groups.first { $0.id == groupId }?.cards ?? []
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(cards.isEmpty ? "All caught up" : VoiceOverFormatter.count(cards.count, singular: "question remaining", plural: "questions remaining"))
                    .font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(cards) { card in
                    AttentionCardView(card: card, onOpen: { onOpen(card) }, onNotNow: { reminderCard = card })
                }
            }.padding(20).readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reminderCard) { AttentionReminderSheet(card: $0) }
    }
}

/// A discoverable reminder option inside a question, in addition to rotor and long-press actions.
struct AttentionDetailReminder: View {
    let card: AttentionCard?
    @State private var showing = false
    var body: some View {
        if let card {
            Button("Remind me later") { showing = true }
                .frame(minHeight: 44)
                .sheet(isPresented: $showing) { AttentionReminderSheet(card: card) }
        }
    }
}
