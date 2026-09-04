//
//  MonthEndReviewView.swift
//  Halo-fi-IOS
//
//  WP6 — the guided month-end pass. One expense per screen: keep or
//  remove, the running total is announced after every action, focus
//  moves to the next card. Confirmed bank charges are listed by
//  description (their amounts live on the Money tab). Nothing here is
//  auto-confirmed — Keep is a deliberate tap.
//

import SwiftUI

struct MonthEndReviewView: View {
    let month: String   // YYYY-MM

    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss

    private enum Item: Identifiable, Equatable {
        case manual(SSIManualDeduction)
        case tagged(SSIExclusion)
        var id: String {
            switch self { case .manual(let m): return "m-\(m.id)"; case .tagged(let e): return "e-\(e.id)" }
        }
    }

    @State private var items: [Item] = []
    @State private var index = 0
    @State private var kept = 0
    @State private var removed = 0
    @State private var runningTotalCents = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isWorking = false
    @AccessibilityFocusState private var cardFocused: Bool

    private let ssiService: SSIServiceProtocol = SSIService.shared

    private var monthLabel: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: month) else { return month }
        let out = DateFormatter(); out.dateFormat = "MMMM yyyy"
        return out.string(from: d)
    }

    private var done: Bool { !isLoading && index >= items.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenReaderSummaryHeader(
                    verdict: done ? "Review complete" : "Review \(monthLabel)",
                    detail: done ? completionLine : progressLine,
                    isEstimate: false,
                    tone: .neutral
                )
                if isLoading {
                    ProgressView("Loading your expenses…").frame(maxWidth: .infinity, minHeight: 88)
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red)
                } else if items.isEmpty {
                    Text("Nothing logged for \(monthLabel) yet. Log an expense from Work expenses and it shows up here.")
                        .foregroundColor(.haloTextSecondary)
                } else if done {
                    completion
                } else {
                    card(items[index])
                    actions
                }
                Text(ScreenReaderSummaryHeader.disclaimer)
                    .font(.caption).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Month-end review")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var progressLine: String {
        guard !items.isEmpty else { return "" }
        return "Expense \(min(index + 1, items.count)) of \(items.count). Running total \(VoiceOverFormatter.dollars(runningTotalCents)). Keep or remove each one."
    }

    private var completionLine: String {
        "\(VoiceOverFormatter.count(kept, singular: "expense kept", plural: "expenses kept")), \(removed) removed. Total \(VoiceOverFormatter.dollars(runningTotalCents)). The package is built from these on the 1st."
    }

    @ViewBuilder
    private func card(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch item {
            case .manual(let m):
                Text(m.vendor ?? m.description).font(.title3.weight(.semibold))
                Text("\(VoiceOverFormatter.dollarsAndCents(m.amountCents)) on \(Self.spokenDate(m.occurredOn)). \(m.exclusionType.rawValue.uppercased()).")
                    .font(.body)
                Text(m.vendor == nil ? "" : m.description).font(.subheadline).foregroundColor(.haloTextSecondary)
                Text(receiptLine(m)).font(.subheadline).foregroundColor(m.hasReceipt ? .haloTextSecondary : .orange)
            case .tagged(let e):
                Text((e.description ?? "").isEmpty ? "Confirmed bank charge" : (e.description ?? "")).font(.title3.weight(.semibold))
                Text("Confirmed from your bank on \(Self.spokenDate(e.confirmedAt)). \(e.exclusionType.rawValue.uppercased()).")
                    .font(.body)
                Text(e.receiptAssetId == nil ? "No receipt attached yet." : "Receipt attached.")
                    .font(.subheadline).foregroundColor(e.receiptAssetId == nil ? .orange : .haloTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($cardFocused)
    }

    private func receiptLine(_ m: SSIManualDeduction) -> String {
        switch m.resolvedMatchStatus {
        case "matched": return "Matched to a bank charge. Receipt \(m.hasReceipt ? "attached" : "still needed")."
        case "waiting_for_bank": return "Receipt attached. Waiting for the bank to show the charge."
        default: return "No receipt yet."
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { advance(keep: true) } label: {
                Label("Keep", systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .accessibilityHint("Keeps this expense in the month's package and moves to the next one.")
            Button(role: .destructive) { Task { await remove() } } label: {
                Label("Remove", systemImage: "trash")
                    .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
            .accessibilityHint("Deletes this expense. It will not be in the package.")
            Button { advance(keep: false) } label: {
                Text("Skip for now").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(completionLine).font(.body).fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: BenefitsHomeView.Route.monthlyPackage(month)) {
                Label("Open the monthly package", systemImage: "doc.text.fill")
                    .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            Button { dismiss() } label: {
                Text("Done").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let manual = ssiService.fetchManualDeductions(userTz: nil, month: month)
            async let tagged = ssiService.fetchExclusions(userTz: nil, month: month)
            let (m, t) = try await (manual, tagged)
            items = m.deductions.map(Item.manual) + t.exclusions.map(Item.tagged)
            runningTotalCents = m.deductions.reduce(0) { $0 + $1.amountCents }
            index = 0; kept = 0; removed = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { cardFocused = true }
        } catch {
            loadError = "Couldn't load \(monthLabel). \(error.localizedDescription)"
        }
    }

    private func advance(keep: Bool) {
        if keep { kept += 1 }
        index += 1
        Haptics.engine.play(.tapLight)
        announce(keep ? "Kept." : "Skipped.")
    }

    private func remove() async {
        guard index < items.count else { return }
        isWorking = true
        defer { isWorking = false }
        let item = items[index]
        do {
            switch item {
            case .manual(let m):
                try await dataManager.deleteManualDeduction(m.id)
                runningTotalCents -= m.amountCents
            case .tagged(let e):
                try await ssiService.deleteExclusion(e.id)
                dataManager.markStale()
            }
            items.remove(at: index)
            removed += 1
            Haptics.success()
            announce("Removed.")
        } catch {
            Haptics.error()
            UIAccessibility.post(notification: .announcement, argument: "Couldn't remove it. \(error.localizedDescription)")
        }
    }

    private func announce(_ prefix: String) {
        let line = done ? "\(prefix) \(completionLine)" : "\(prefix) \(progressLine)"
        UIAccessibility.post(notification: .announcement, argument: line)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { cardFocused = true }
    }

    private static func spokenDate(_ iso: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMMM d"
        return out.string(from: d)
    }
}
