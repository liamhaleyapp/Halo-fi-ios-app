//
//  TransactionPickerView.swift
//  Halo-fi-IOS
//
//  "Find it in your transactions" for the work-expense form (Liam,
//  2026-09-05): search the bank feed by name — Uber, Walgreens — and pick
//  the charge; the form fills in amount, date and description and the
//  expense is logged against that transaction.
//

import SwiftUI

struct TransactionPickerView: View {
    let bankDataManager: BankDataManager
    let onPick: (Transaction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var all: [Transaction] = []
    @State private var isLoading = true
    @AccessibilityFocusState private var searchFocused: Bool

    private var results: [Transaction] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let outflows = all.filter { $0.amount > 0 }   // charges, not deposits
        guard !q.isEmpty else { return Array(outflows.prefix(60)) }
        return outflows.filter { ($0.merchantName ?? "").lowercased().contains(q) || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading && all.isEmpty {
                    Text("Loading your transactions…").foregroundColor(.haloTextSecondary)
                } else if results.isEmpty {
                    Text(query.isEmpty ? "No charges found yet. Pull to refresh on the Money tab, then try again."
                                       : "Nothing matches \"\(query)\". Try a shorter word, like the first part of the name.")
                        .foregroundColor(.haloTextSecondary)
                }
                ForEach(results) { tx in
                    Button {
                        onPick(tx)
                        dismiss()
                    } label: {
                        row(tx)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(tx))
                    .accessibilityHint("Fills in the expense from this charge.")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name, like Uber")
            .navigationTitle("Your transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseToolbarButton(label: "Cancel", hint: "Goes back to the form without picking a charge.") { dismiss() }
                }
            }
            .accessibilityAction(.escape) { dismiss() }
            .task {
                all = await bankDataManager.allTransactions(forceRefresh: false, limit: 300)
                isLoading = false
                if all.isEmpty {
                    all = await bankDataManager.allTransactions(forceRefresh: true, limit: 300)
                }
            }
        }
    }

    private func row(_ tx: Transaction) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.merchantName ?? tx.name).font(.body.weight(.semibold)).foregroundColor(.haloTextPrimary).lineLimit(1)
                Text("\(Self.spokenDate(tx.transactionDate))\(accountSuffix(tx))")
                    .font(.caption).foregroundColor(.haloTextSecondary)
            }
            Spacer()
            Text(Self.dollars(tx.amount)).font(.body.weight(.semibold)).foregroundColor(.haloTextPrimary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func label(_ tx: Transaction) -> String {
        "\(tx.merchantName ?? tx.name), \(VoiceOverFormatter.dollarsAndCents(Int((abs(tx.amount) * 100).rounded()))), \(Self.spokenDate(tx.transactionDate))\(accountSuffix(tx))\(tx.pending ? ", pending" : "")"
    }

    private func accountSuffix(_ tx: Transaction) -> String {
        guard let account = bankDataManager.accountLabel(for: tx.accountId) else { return "" }
        return ", \(account)"
    }

    private static let isoDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private static func spokenDate(_ iso: String) -> String {
        guard let d = isoDate.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMMM d"; return out.string(from: d)
    }

    private static func dollars(_ amount: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: NSNumber(value: abs(amount))) ?? String(format: "$%.2f", abs(amount))
    }
}
