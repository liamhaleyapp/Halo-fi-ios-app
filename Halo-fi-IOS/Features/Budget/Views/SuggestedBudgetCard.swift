//
//  SuggestedBudgetCard.swift
//  Halo-fi-IOS
//
//  WP5 — "Suggested budget" (top of BudgetView, below the summary header):
//  per-category medians from the last 90 days and one button, "Use this
//  budget". Also the add-category sheet and the inline limit editor used
//  by BudgetCategoryListView. Every change announces the new monthly total.
//

import SwiftUI

struct SuggestedBudgetCard: View {
    let suggestion: BudgetSuggestion
    let hasBudget: Bool
    let onApply: () async -> Void

    @State private var isApplying = false
    @State private var expanded = false

    private var totalLine: String {
        "Suggested \(VoiceOverFormatter.dollars(suggestion.totalLimitCents)) a month across \(VoiceOverFormatter.count(suggestion.proposal.count, singular: "category", plural: "categories")), from your last \(suggestion.windowDays) days."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(.yellow).accessibilityHidden(true)
                Text(hasBudget ? "A fresher budget is ready" : "Suggested budget")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            Text(totalLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if expanded {
                VStack(spacing: 6) {
                    ForEach(suggestion.rows) { row in
                        HStack {
                            Text(BudgetFormatter.displayName(forCategory: row.category))
                                .font(.subheadline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(BudgetFormatter.cents(row.limitCents)).font(.subheadline.weight(.semibold))
                                if let median = row.medianCents {
                                    Text("you usually spend \(BudgetFormatter.cents(median))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(rowLabel(row))
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Text(expanded ? "Hide categories" : "See categories")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button {
                    isApplying = true
                    Task {
                        await onApply()
                        isApplying = false
                    }
                } label: {
                    if isApplying {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Text("Use this budget").frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying)
                .accessibilityHint(hasBudget ? "Replaces your current budget with the suggested limits." : "Creates your budget from these limits. You can edit any category after.")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested budget. \(totalLine)")
    }

    private func rowLabel(_ row: BudgetSuggestion.Row) -> String {
        var s = "\(BudgetFormatter.displayName(forCategory: row.category)), \(VoiceOverFormatter.dollars(row.limitCents))."
        if let median = row.medianCents { s += " You usually spend \(VoiceOverFormatter.dollars(median))." }
        return s
    }
}

// MARK: - Add category

struct AddCategorySheet: View {
    let existing: Set<String>
    let onAdd: (String, Double) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: String = ""
    @State private var amountText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let codes = [
        "food_and_drink", "transportation", "entertainment", "general_merchandise", "home_improvement",
        "medical", "personal_care", "general_services", "rent_and_utilities", "loan_payments", "travel",
        "government_and_non_profit", "uncategorized",
    ]

    private var available: [String] { Self.codes.filter { !existing.contains($0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $category) {
                        Text("Choose…").tag("")
                        ForEach(available, id: \.self) { code in
                            Text(BudgetFormatter.displayName(forCategory: code)).tag(code)
                        }
                    }
                    TextField("Monthly limit", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Monthly limit in dollars")
                } footer: {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Add") { save() }
                        .disabled(isSaving || category.isEmpty || Double(amountText) == nil)
                }
            }
            .accessibilityAction(.escape) { dismiss() }
        }
    }

    private func save() {
        guard let amount = Double(amountText), amount >= 0 else { return }
        isSaving = true
        Task {
            do {
                try await onAdd(category, amount)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = "Couldn't add it. \(error.localizedDescription)"
                UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
            }
        }
    }
}
