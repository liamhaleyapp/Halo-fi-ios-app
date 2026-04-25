//
//  SSIDeductionConfirmView.swift
//  Halo-fi-IOS
//
//  Sheet presented when the backend classifier flags a transaction
//  as a possible Blind Work Expense or Impairment-Related Work
//  Expense (Phase 3 of the SSI rules-engine rebuild). The user picks
//  whether to confirm the suggested type, switch to the other
//  bucket, or dismiss without writing anything.
//
//  Per §4.1 of the rules engine: for blind users, $1 of BWE
//  preserves $1.00 of SSI vs $0.50 for IRWE. The sheet surfaces this
//  trade-off explicitly so the user can pick the higher-value bucket
//  if their expense plausibly fits both.
//

import SwiftUI

struct SSIDeductionConfirmView: View {
    let candidate: SSIDeductionCandidate

    /// Called with the type the user confirmed. Caller writes to the
    /// API, refreshes Budget data, and dismisses the sheet. Nil means
    /// the user dismissed without confirming.
    let onConfirm: (SSIExclusionType) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: SSIExclusionType
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        candidate: SSIDeductionCandidate,
        onConfirm: @escaping (SSIExclusionType) async -> Void
    ) {
        self.candidate = candidate
        self.onConfirm = onConfirm
        _selectedType = State(initialValue: candidate.suggestedType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    transactionSummary
                } header: {
                    Text("Transaction").textCase(nil)
                }

                Section {
                    Text(candidate.reason)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isStaticText)
                } header: {
                    Text("Why we flagged it").textCase(nil)
                }

                Section {
                    typePicker
                } header: {
                    Text("Classify as").textCase(nil)
                } footer: {
                    Text(typeFooter)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Confirm as \(selectedType.label)")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSubmitting)
                    .accessibilityHint(
                        "Adds this transaction to your monthly \(selectedType.label) total."
                    )
                }
            }
            .navigationTitle("Possible deduction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .accessibilityHint("Dismisses without saving.")
                }
            }
        }
    }

    @ViewBuilder
    private var transactionSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.description.isEmpty ? "Transaction" : candidate.description)
                .font(.headline)
            HStack {
                Text(BudgetFormatter.cents(candidate.amountCents))
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(candidate.transactionDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(candidate.description). Amount \(BudgetFormatter.cents(candidate.amountCents)). Dated \(candidate.transactionDate)."
        )
    }

    @ViewBuilder
    private var typePicker: some View {
        Picker("Type", selection: $selectedType) {
            ForEach(SSIExclusionType.allCases, id: \.self) { type in
                Text(type.label).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Choose Blind Work Expense, Impairment-Related Work Expense, or Burial Fund.")
    }

    private var typeFooter: String {
        switch selectedType {
        case .bwe:
            return "Blind Work Expense — preserves $1 of SSI for every $1 spent."
        case .irwe:
            return "Impairment-Related Work Expense — preserves about $0.50 of SSI per $1 spent."
        case .burial:
            return "Designated burial-fund deposit — excluded from countable resources up to $1,500."
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        await onConfirm(selectedType)
        isSubmitting = false
        dismiss()
    }
}

private extension SSIExclusionType {
    var label: String {
        switch self {
        case .bwe: return "BWE"
        case .irwe: return "IRWE"
        case .burial: return "Burial"
        }
    }
}
