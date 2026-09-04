//
//  BudgetCategoryListView.swift
//  Halo-fi-IOS
//
//  Dedicated screen for the per-category breakdown. The main Budget tab
//  keeps the hero + income + SSI concise; users who want the full list
//  tap "Breakdown by Category" to land here.
//
//  Shape matches AccountsOverviewView: LazyVStack + Section { } header:
//  { sectionHeader } with value-based navigation into
//  BudgetCategoryDetailView.
//

import SwiftUI

struct BudgetCategoryListView: View {
    // Scales with Dynamic Type (App Store Guideline 4).
    @ScaledMetric(relativeTo: .largeTitle) private var emptyIconSize: CGFloat = 40
    @Environment(BudgetDataManager.self) private var dataManager
    // WP5 — inline editing
    @State private var editingCategory: BudgetStatusCategory?
    @State private var editLimitText: String = ""
    @State private var showingAddCategory = false
    @State private var editError: String?

    var body: some View {
        ZStack {
            Color.haloBackground.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 12) {
                    if let overview = dataManager.overview {
                        body(for: overview)
                    } else if dataManager.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else if let err = dataManager.error {
                        Text(err.errorDescription ?? "Couldn't load categories.")
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .refreshable { await dataManager.refresh() }
        }
        .navigationTitle("Breakdown")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if dataManager.overview?.budgetStatus.hasBudget == true {
                    Button { showingAddCategory = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add category")
                        .accessibilityHint("Adds a category with a monthly limit to your budget.")
                }
            }
        }
        .alert("Edit limit", isPresented: Binding(get: { editingCategory != nil }, set: { if !$0 { editingCategory = nil } })) {
            TextField("Monthly limit in dollars", text: $editLimitText)
                .keyboardType(.decimalPad)
            Button("Save") { commitEdit() }
            Button("Cancel", role: .cancel) { editingCategory = nil }
        } message: {
            if let cat = editingCategory {
                Text("\(BudgetFormatter.displayName(forCategory: cat.category)) — currently \(cat.formatted["limit"] ?? "")")
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet(
                existing: Set((dataManager.overview?.budgetStatus.categories ?? []).map { $0.category }),
                onAdd: { code, amount in try await dataManager.addCategory(code: code, limitAmount: amount) }
            )
        }
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for overview: BudgetOverview) -> some View {
        if overview.budgetStatus.hasBudget, !overview.budgetStatus.categories.isEmpty {
            groupedBudgetSections(overview.budgetStatus.categories)
        } else if !overview.spending.groups.isEmpty {
            spendingOnlySection(overview.spending.groups)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: emptyIconSize))
                .foregroundStyle(.secondary)
            Text("No category spending yet this month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Grouped (with budget)

    /// Group budget categories into status-ordered sections. Mirrors
    /// AccountsOverviewView's "Connected" / "Needs Attention" grouping.
    @ViewBuilder
    private func groupedBudgetSections(_ categories: [BudgetStatusCategory]) -> some View {
        let grouped = Dictionary(grouping: categories, by: { $0.status })
        let ordering: [(status: String, title: String)] = [
            ("over",    "Over Budget"),
            ("behind",  "Behind"),
            ("on_pace", "On Pace"),
            ("ahead",   "Ahead"),
        ]

        ForEach(ordering, id: \.status) { group in
            if let rows = grouped[group.status], !rows.isEmpty {
                Section {
                    ForEach(rows) { cat in
                        // Closure-based to match the rest of the Budget
                        // navigation stack — value-based here while the
                        // list itself was pushed via closure caused
                        // SwiftUI to flash the destination then bounce
                        // back to this list view.
                        NavigationLink {
                            BudgetCategoryDetailView(category: cat)
                        } label: {
                            BudgetCategoryRow(category: cat)
                        }
                        .buttonStyle(HapticPlainButtonStyle())
                        // WP5 — the extra verbs live in the rotor and the
                        // context menu; the row stays one element.
                        .accessibilityAction(named: "Edit limit") { beginEdit(cat) }
                        .accessibilityAction(named: "Remove category") { remove(cat) }
                        .contextMenu {
                            Button { beginEdit(cat) } label: { Label("Edit limit", systemImage: "pencil") }
                            Button(role: .destructive) { remove(cat) } label: { Label("Remove category", systemImage: "trash") }
                        }
                    }
                } header: {
                    sectionHeader(group.title, count: rows.count)
                }
            }
        }
    }

    // MARK: - WP5 editing

    private func beginEdit(_ cat: BudgetStatusCategory) {
        editLimitText = String(format: "%.2f", Double(cat.limitCents) / 100.0)
        editingCategory = cat
    }

    private func commitEdit() {
        guard let cat = editingCategory, let id = cat.categoryId, let dollars = Double(editLimitText), dollars >= 0 else {
            editingCategory = nil
            return
        }
        editingCategory = nil
        Task {
            do {
                try await dataManager.saveCategoryLimit(categoryId: id, limitAmount: dollars, announce: true)
            } catch {
                Haptics.error()
                UIAccessibility.post(notification: .announcement, argument: "Couldn't update the limit. \(error.localizedDescription)")
            }
        }
    }

    private func remove(_ cat: BudgetStatusCategory) {
        Task {
            do {
                try await dataManager.deleteCategory(cat)
            } catch {
                Haptics.error()
                UIAccessibility.post(notification: .announcement, argument: "Couldn't remove the category. \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Spending-only (no budget)

    @ViewBuilder
    private func spendingOnlySection(_ groups: [BudgetSpendingGroup]) -> some View {
        Section {
            ForEach(groups) { group in
                BudgetSpendingOnlyRow(group: group)
            }
        } header: {
            sectionHeader("Spending by Category", count: groups.count)
        }
    }

    // MARK: - Section header (match AccountsOverviewView)

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(Color.haloTextSecondary)
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .foregroundColor(Color.haloTextSecondary)
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title), \(count) item\(count == 1 ? "" : "s")")
    }
}

// MARK: - Row: budgeted category (tappable)

struct BudgetCategoryRow: View {
    let category: BudgetStatusCategory

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(BudgetFormatter.displayName(forCategory: category.category))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(category.formatted["spent"] ?? "$0.00")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("of \(category.formatted["limit"] ?? "$0.00")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                progressBar
            }
            pctLabel
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to see category details.")
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(BudgetFormatter.color(forCategory: category.category).opacity(0.22))
                .frame(width: 36, height: 36)
            Image(systemName: BudgetFormatter.iconName(forCategory: category.category))
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
        .frame(height: 4)
    }

    private var pctLabel: some View {
        Text("\(Int(category.pctUsed.rounded()))%")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(BudgetFormatter.color(forStatus: category.status))
            .frame(minWidth: 36, alignment: .trailing)
    }

    private var accessibilityLabel: String {
        let name = BudgetFormatter.displayName(forCategory: category.category)
        let spent = category.formatted["spent"] ?? "zero dollars"
        let limit = category.formatted["limit"] ?? "zero dollars"
        let pct = Int(category.pctUsed.rounded())
        let status = category.status.replacingOccurrences(of: "_", with: " ")
        return "\(name): \(spent) of \(limit), \(pct) percent used. Status: \(status)."
    }
}

// MARK: - Row: spending-only (no budget)

struct BudgetSpendingOnlyRow: View {
    let group: BudgetSpendingGroup

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(BudgetFormatter.color(forCategory: group.key).opacity(0.22))
                    .frame(width: 36, height: 36)
                Image(systemName: BudgetFormatter.iconName(forCategory: group.key))
                    .foregroundStyle(BudgetFormatter.color(forCategory: group.key))
            }
            Text(BudgetFormatter.displayName(forCategory: group.key))
                .font(.subheadline)
            Spacer()
            Text(group.formatted)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("\(Int(group.pctOfTotal.rounded()))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(BudgetFormatter.displayName(forCategory: group.key)): \(group.formatted), \(Int(group.pctOfTotal.rounded())) percent of spending.")
    }
}
