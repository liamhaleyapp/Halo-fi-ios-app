//
//  BudgetCategoryDetailView.swift
//  Halo-fi-IOS
//
//  Drill-down view shown when the user taps a row in the SPENDING BY
//  CATEGORY list on BudgetView. Scope is intentionally narrow for this
//  pass — hero, progress, pace/status. No transaction list yet.
//

import SwiftUI

struct BudgetCategoryDetailView: View {
    let category: BudgetStatusCategory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                statusCard
                paceCard
            }
            .padding()
        }
        .navigationTitle(BudgetFormatter.displayName(forCategory: category.category))
        .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private var paceCard: some View {
        if category.limitCents > 0 {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Limit")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Spend under this to stay on pace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(category.formatted["limit"] ?? "$0.00")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
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
