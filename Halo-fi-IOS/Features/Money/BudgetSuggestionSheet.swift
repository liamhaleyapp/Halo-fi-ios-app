//
//  BudgetSuggestionSheet.swift
//  Halo-fi-IOS
//
//  Budget on autopilot (2026-09-06): the fresh proposal from the last 90
//  days is one tap. Keep what you have, or use it.
//

import SwiftUI

struct BudgetSuggestionSheet: View {
    let card: AttentionCard
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var focused: Bool

    private var total: Int { card.payload.totalLimitCents ?? 0 }
    private var count: Int { card.payload.categoryCount ?? 0 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(card.title).font(.title2.weight(.bold)).foregroundColor(.haloTextPrimary)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($focused)
                Text("\(BudgetFormatter.cents(total)) a month across \(VoiceOverFormatter.count(count, singular: "category", plural: "categories")), from what you actually spent over the last \(card.payload.windowDays ?? 90) days.")
                    .font(.body).foregroundColor(.haloTextSecondary).fixedSize(horizontal: false, vertical: true)
                if let suggestion = dataManager.suggestion, !suggestion.proposal.isEmpty {
                    let rows = suggestion.proposal.sorted { $0.value > $1.value }.prefix(8)
                    VStack(spacing: 6) {
                        ForEach(Array(rows), id: \.key) { row in
                            HStack {
                                Text(BudgetFormatter.displayName(forCategory: row.key)).font(.subheadline)
                                Spacer()
                                Text(BudgetFormatter.cents(row.value)).font(.subheadline.weight(.semibold))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Button { apply() } label: {
                    Text(isSaving ? "Saving…" : (card.payload.hasBudget == true ? "Use this budget" : "Start this budget"))
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent).disabled(isSaving)
                .accessibilityHint(card.payload.hasBudget == true ? "Replaces your current limits with these. You can edit any category after." : "Creates your budget from these limits.")
                Button { Task { await dataManager.dismissCard(card, days: 30) }; dismiss() } label: {
                    Text(card.payload.hasBudget == true ? "Keep what I have" : "Not now")
                        .font(.subheadline).foregroundColor(.haloTextSecondary).frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(isSaving)
                if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
                Spacer()
            }
            .padding(20).readableContentWidth()
            .background(Color.haloBackground.ignoresSafeArea())
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { CloseToolbarButton { dismiss() } } }
            .accessibilityAction(.escape) { dismiss() }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true } }
            .task { if dataManager.suggestion == nil { await dataManager.fetchSuggestion() } }
        }
    }

    private func apply() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await dataManager.applySuggestion()
                dataManager.resolveCard(card)
                isSaving = false
                Haptics.success()
                UIAccessibility.post(notification: .announcement, argument: "Budget set: \(VoiceOverFormatter.dollars(total)) a month.")
                dismiss()
            } catch {
                isSaving = false
                Haptics.error()
                errorMessage = "Couldn't set the budget. \(error.localizedDescription)"
                UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
            }
        }
    }
}
