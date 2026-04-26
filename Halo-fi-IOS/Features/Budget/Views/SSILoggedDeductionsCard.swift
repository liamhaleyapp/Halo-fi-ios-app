//
//  SSILoggedDeductionsCard.swift
//  Halo-fi-IOS
//
//  Phase 8 — combined view of manual SSI deductions for the current
//  month. Each row shows amount, description, type, and where it
//  came from (voice vs UI entry). Swipe-to-delete removes the row
//  and triggers a budget overview refresh so projected SSI updates.
//
//  A "+ Add manually" button opens a sheet that mirrors the voice
//  flow — same fields, same defaulting rules. Voice-driven entries
//  arrive via the agent calling add_ssi_deduction, no UI needed.
//

import SwiftUI

struct SSILoggedDeductionsCard: View {
    let deductions: [SSIManualDeduction]
    let totalsCents: [String: Int]
    let isBlind: Bool
    let onAdd: () -> Void
    let onDelete: (SSIManualDeduction) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logged deductions")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let line = totalsLine {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add a manual SSI deduction")
            }

            if deductions.isEmpty {
                Text("Nothing logged this month yet. Tell Halo \"save \(isBlind ? "fifty dollars on Uber as a BWE" : "fifty dollars on copays as IRWE")\", or tap Add.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(deductions) { entry in
                        deductionRow(entry)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private func deductionRow(_ entry: SSIManualDeduction) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(typeBadge(entry.exclusionType))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeBg(entry.exclusionType), in: Capsule())
                        .foregroundStyle(badgeFg(entry.exclusionType))
                    if entry.source == "user_voice" {
                        Image(systemName: "mic.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Logged by voice")
                    }
                }
                Text(entry.description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(BudgetFormatter.cents(entry.amountCents)) on \(formattedDate(entry.occurredOn))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                Task { await onDelete(entry) }
            } label: {
                Image(systemName: "trash")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(entry.description) deduction")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(entry))
    }

    private var totalsLine: String? {
        let bwe = totalsCents["bwe"] ?? 0
        let irwe = totalsCents["irwe"] ?? 0
        let burial = totalsCents["burial"] ?? 0
        var parts: [String] = []
        if bwe > 0 { parts.append("BWE \(BudgetFormatter.cents(bwe))") }
        if irwe > 0 { parts.append("IRWE \(BudgetFormatter.cents(irwe))") }
        if burial > 0 { parts.append("Burial \(BudgetFormatter.cents(burial))") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ") + " this month"
    }

    private func typeBadge(_ type: SSIExclusionType) -> String {
        switch type {
        case .bwe: return "BWE"
        case .irwe: return "IRWE"
        case .burial: return "BURIAL"
        }
    }

    private func badgeBg(_ type: SSIExclusionType) -> Color {
        switch type {
        case .bwe: return .green.opacity(0.18)
        case .irwe: return .orange.opacity(0.18)
        case .burial: return .blue.opacity(0.18)
        }
    }

    private func badgeFg(_ type: SSIExclusionType) -> Color {
        switch type {
        case .bwe: return .green
        case .irwe: return .orange
        case .burial: return .blue
        }
    }

    private func formattedDate(_ iso: String) -> String {
        // Backend hands us either YYYY-MM-DD or a full ISO timestamp;
        // chop to the date prefix and parse.
        let prefix = String(iso.prefix(10))
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = inputFormatter.date(from: prefix) else { return prefix }
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM d"
        return outputFormatter.string(from: date)
    }

    private func rowAccessibilityLabel(_ entry: SSIManualDeduction) -> String {
        let typeLabel: String
        switch entry.exclusionType {
        case .bwe: typeLabel = "Blind Work Expense"
        case .irwe: typeLabel = "Impairment-Related Work Expense"
        case .burial: typeLabel = "Burial-fund deposit"
        }
        let sourceLabel = entry.source == "user_voice" ? "Logged by voice" : "Logged manually"
        return "\(typeLabel). \(entry.description). \(BudgetFormatter.cents(entry.amountCents)) on \(formattedDate(entry.occurredOn)). \(sourceLabel)."
    }
}
