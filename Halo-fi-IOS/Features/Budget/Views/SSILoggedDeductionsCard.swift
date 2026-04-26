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
    /// Phase 9 — closure that fetches the CSV bytes and returns a
    /// temp-file URL for sharing. nil disables the Export button
    /// (used in previews/tests).
    let onExport: (() async throws -> URL)?

    @State private var isExporting = false
    @State private var exportedFile: ExportedCSVFile?
    @State private var exportError: String?

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
                if let onExport, !deductions.isEmpty {
                    Button {
                        Task { await runExport(onExport) }
                    } label: {
                        if isExporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isExporting)
                    .accessibilityLabel("Export this month's SSI deductions as a CSV file")
                    .accessibilityHint("Opens the share sheet so you can email or save the file.")
                }
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add a manual SSI deduction")
            }
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Export failed: \(exportError)")
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
        .sheet(item: $exportedFile) { file in
            CSVShareSheet(url: file.url) { exportedFile = nil }
        }
    }

    private func runExport(_ provider: () async throws -> URL) async {
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            exportedFile = ExportedCSVFile(url: try await provider())
        } catch {
            exportError = "Couldn't generate the file. Try again in a moment."
        }
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
                    if entry.linkedTransactionId != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Matched to bank transaction")
                    }
                }
                Text(entry.description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(BudgetFormatter.cents(entry.amountCents)) on \(formattedDate(entry.occurredOn))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let line = matchStatusLine(entry) {
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(matchStatusColor(entry))
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                Task {
                    await onDelete(entry)
                    // Track C — haptic confirm after the network
                    // round-trip. Blind users feel "done" without
                    // waiting for the row to disappear visually.
                    Haptics.success()
                }
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

    /// Phase 8b — render the bank-matching status. Three states:
    /// matched, waiting (recent), waiting (stale → keep receipt).
    private func matchStatusLine(_ entry: SSIManualDeduction) -> String? {
        // Only voice-logged entries auto-reconcile; manual UI
        // entries don't promise a match because the user already
        // typed the data deliberately.
        guard entry.source == "user_voice" else { return nil }
        if entry.linkedAt != nil {
            return "Matched to bank transaction"
        }
        if isOlderThanGracePeriod(entry) {
            return "No matching bank charge yet — keep your receipt"
        }
        return "Waiting for bank to confirm"
    }

    private func matchStatusColor(_ entry: SSIManualDeduction) -> Color {
        if entry.linkedTransactionId != nil { return .green }
        if isOlderThanGracePeriod(entry) { return .orange }
        return .secondary
    }

    /// 7 days is the unofficial Plaid settle SLA. After that, a
    /// missing match probably means cash / out-of-band purchase
    /// and the user should rely on their receipt for SSA proof.
    private func isOlderThanGracePeriod(_ entry: SSIManualDeduction) -> Bool {
        let prefix = String(entry.occurredOn.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: prefix) else { return false }
        return Date().timeIntervalSince(date) > 7 * 24 * 60 * 60
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
        var parts = [
            "\(typeLabel).",
            "\(entry.description).",
            "\(BudgetFormatter.cents(entry.amountCents)) on \(formattedDate(entry.occurredOn)).",
            "\(sourceLabel).",
        ]
        if let status = matchStatusLine(entry) {
            parts.append("\(status).")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - URL share sheet bridge

/// Wrapping URL in a private Identifiable struct avoids colliding
/// with Foundation's URL: Identifiable conformance on iOS 16+.
struct ExportedCSVFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Wraps `UIActivityViewController` so the SwiftUI `.sheet` can
/// present it for sharing the CSV. `onDismiss` clears the parent's
/// state binding and the temp file is left for the OS to clean up.
private struct CSVShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onDismiss() }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
