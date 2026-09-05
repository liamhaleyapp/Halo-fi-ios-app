//
//  AttentionStack.swift
//  Halo-fi-IOS
//
//  "Needs your attention" under the balance card (Liam, 2026-09-05): up
//  to three cards, most urgent first, each one VoiceOver element and one
//  tap. Deadlines (resources, package, receipts, a bank to reconnect)
//  navigate; learning questions (a deposit, a paycheck's gross, a likely
//  work expense) open a one-question sheet. "Not now" hides a card for a
//  week. Words carry the state, never color alone.
//

import SwiftUI

struct AttentionStack: View {
    let cards: [AttentionCard]
    let moreCount: Int
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
                Text("Nothing needs you right now.")
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
        default: return "Opens it."
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.headline).foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.line).font(.subheadline).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.haloTextTertiary).accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 64)
            .background(card.learn ? Color.haloSecondaryBackground : tint.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(card.learn ? Color.clear : tint.opacity(0.45), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
