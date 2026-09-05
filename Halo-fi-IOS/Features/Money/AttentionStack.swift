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

struct AttentionView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    let onOpen: (AttentionCard) -> Void

    private var cards: [AttentionCard] { dataManager.attentionCards + dataManager.attentionQueue }

    private var tone: ScreenReaderSummaryHeader.Tone {
        switch cards.first?.tone {
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
                    verdict: cards.isEmpty
                        ? "Nothing needs you right now"
                        : VoiceOverFormatter.count(cards.count, singular: "thing needs you", plural: "things need you"),
                    detail: cards.isEmpty
                        ? "New deposits, charges and deadlines show up here as they arrive."
                        : "Most urgent first. Open one to handle it. Not now hides it for a week.",
                    tone: tone
                )
                ForEach(cards) { card in
                    AttentionCardView(card: card, onOpen: { onOpen(card) }, onNotNow: {
                        Task {
                            await dataManager.dismissCard(card)
                            let left = cards.count
                            UIAccessibility.post(notification: .announcement,
                                                 argument: "Hidden for a week. " + (left == 0 ? "Nothing else needs you." : VoiceOverFormatter.count(left, singular: "thing left", plural: "things left") + "."))
                        }
                    })
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 100)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
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
        case "profile_incomplete": return "person.text.rectangle.fill"
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
        default: return "Opens it."
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 14) {
                HaloIconTile(icon: icon, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title).font(.haloRowTitle).foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.line).font(.subheadline).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundColor(.haloTextTertiary).accessibilityHidden(true)
            }
            .padding(16)
            .frame(minHeight: 72)
            .haloCard(tint: card.learn ? nil : tint)
        }
        .buttonStyle(HapticPlainButtonStyle())
        .contextMenu {
            Button { onNotNow() } label: { Label("Not now", systemImage: "clock") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.title). \(card.line)")
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Not now") { onNotNow() }
        .accessibilityIdentifier("attentionCard-\(card.kind)")
    }
}
