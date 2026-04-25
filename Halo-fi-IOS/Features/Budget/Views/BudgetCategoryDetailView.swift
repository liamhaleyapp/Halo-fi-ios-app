//
//  BudgetCategoryDetailView.swift
//  Halo-fi-IOS
//
//  Drill-down view shown when the user taps a row in the SPENDING BY
//  CATEGORY list on BudgetView. Hero, progress, status, and an editable
//  monthly limit (PATCH /budget/categories/{id}).
//
//  The view holds an `initial` snapshot of the category passed in by the
//  navigation push, then prefers the latest value from BudgetDataManager
//  on every render so saving a new limit (which triggers a refresh)
//  immediately reflects in the visible numbers.
//

import SwiftUI

struct BudgetCategoryDetailView: View {
    let initial: BudgetStatusCategory
    @Environment(BudgetDataManager.self) private var dataManager
    @State private var showingLimitEditor = false

    /// Latest version of this category from the data manager, or the
    /// initial snapshot if the manager hasn't refreshed yet (or the
    /// category was removed mid-refresh).
    private var category: BudgetStatusCategory {
        dataManager.overview?.budgetStatus.categories
            .first(where: { $0.category == initial.category })
            ?? initial
    }

    init(category: BudgetStatusCategory) {
        self.initial = category
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                statusCard
                limitCard
            }
            .padding()
        }
        .navigationTitle(BudgetFormatter.displayName(forCategory: category.category))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLimitEditor) {
            CategoryLimitEditorView(category: category)
        }
    }

    // MARK: - Cards

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                categoryIconLarge
                VStack(alignment: .leading, spacing: 2) {
                    Text(BudgetFormatter.displayName(forCategory: category.category))
                        .font(.headline)
                    Text("This month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(category.formatted["spent"] ?? "$0.00")
                    .font(.system(size: 40, weight: .bold))
                Text("of \(category.formatted["limit"] ?? "$0.00")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            progressBar

            HStack {
                Text("\(Int(category.pctUsed.rounded()))% used")
                Spacer()
                Text("\(category.formatted["remaining"] ?? "$0.00") remaining")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heroAccessibilityLabel)
    }

    private var statusCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Status")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(statusExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(BudgetFormatter.prettyStatus(category.status))
                .font(.footnote)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.2), in: Capsule())
                .foregroundStyle(statusColor)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(BudgetFormatter.prettyStatus(category.status)). \(statusExplanation)")
    }

    /// Limit card — tappable when we have a category id from the backend.
    /// Older API responses without category_id render the same card as
    /// read-only, no edit affordance, no crash.
    @ViewBuilder
    private var limitCard: some View {
        let canEdit = category.categoryId != nil
        let card = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Limit")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(canEdit ? "Tap to change this limit" : "Spend under this to stay on pace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(category.formatted["limit"] ?? "$0.00")
                .font(.subheadline)
                .fontWeight(.medium)
            if canEdit {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(limitAccessibilityLabel(canEdit: canEdit))
        .accessibilityHint(canEdit ? "Double-tap to change the limit." : "")

        if canEdit {
            Button { showingLimitEditor = true } label: { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    // MARK: - Pieces

    private var categoryIconLarge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(BudgetFormatter.color(forCategory: category.category).opacity(0.2))
                .frame(width: 56, height: 56)
            Image(systemName: BudgetFormatter.iconName(forCategory: category.category))
                .font(.title2)
                .foregroundStyle(BudgetFormatter.color(forCategory: category.category))
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let pct = min(max(category.pctUsed / 100.0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemBackground))
                Capsule()
                    .fill(BudgetFormatter.color(forCategory: category.category))
                    .frame(width: geo.size.width * CGFloat(pct))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true) // announced via heroAccessibilityLabel
    }

    private var heroAccessibilityLabel: String {
        let name = BudgetFormatter.displayName(forCategory: category.category)
        let spent = category.formatted["spent"] ?? "zero dollars"
        let limit = category.formatted["limit"] ?? "zero dollars"
        let remaining = category.formatted["remaining"] ?? "zero dollars"
        let pct = Int(category.pctUsed.rounded())
        return "\(name) this month. Spent \(spent) of \(limit) limit. \(pct) percent used. \(remaining) remaining."
    }

    private func limitAccessibilityLabel(canEdit: Bool) -> String {
        let limit = category.formatted["limit"] ?? "zero dollars"
        if canEdit {
            return "Limit: \(limit). Tap to change."
        }
        return "Limit: \(limit). Spend under this to stay on pace."
    }

    // MARK: - Status helpers

    private var statusColor: Color {
        BudgetFormatter.color(forStatus: category.status)
    }

    private var statusExplanation: String {
        switch category.status {
        case "over":
            return "You've exceeded the limit for this category."
        case "behind":
            return "Spending is running faster than the month's pace."
        case "ahead":
            return "Well under pace — room to spare."
        case "on_pace":
            return "Tracking with the month."
        default:
            return ""
        }
    }
}

// MARK: - Limit editor sheet

private struct CategoryLimitEditorView: View {
    let category: BudgetStatusCategory

    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("New monthly limit in dollars")
                    }
                } header: {
                    Text("Monthly limit")
                } footer: {
                    Text("Sets the spending target for \(BudgetFormatter.displayName(forCategory: category.category)) each month.")
                        .font(.caption)
                }

                if let err = saveError {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving || parsedAmount == nil)
                }
            }
            .onAppear { seed() }
        }
    }

    // MARK: - Actions

    private func seed() {
        // Pre-fill the field with the current limit so the user can edit
        // rather than re-type from scratch.
        amountText = String(format: "%.2f", Double(category.limitCents) / 100.0)
    }

    private var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        guard let categoryId = category.categoryId else {
            saveError = "Can't update — missing category id. Try again after refreshing."
            return
        }

        isSaving = true
        saveError = nil
        Task {
            do {
                try await dataManager.saveCategoryLimit(
                    categoryId: categoryId,
                    limitAmount: amount
                )
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                saveError = "Couldn't save: \(error.localizedDescription)"
            }
        }
    }
}
