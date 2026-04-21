//
//  IncomeEditorView.swift
//  Halo-fi-IOS
//
//  Sheet presented from BudgetView for editing the user's monthly
//  income sources (paycheck, SSI, SSDI). Only sends fields the user
//  actually changed — the backend PATCH /users/me applies diffs.
//

import SwiftUI

struct IncomeEditorView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss

    // Paycheck
    @State private var paycheckAmount: String = ""
    @State private var payFrequency: String = "biweekly"
    @State private var paycheckName: String = ""

    // SSI
    @State private var receivesSSI: Bool = false
    @State private var ssiAmount: String = ""

    // SSDI
    @State private var receivesSSDI: Bool = false
    @State private var ssdiAmount: String = ""

    @State private var isSaving = false
    @State private var saveError: String?

    private let frequencies = [
        ("weekly", "Weekly"),
        ("biweekly", "Every two weeks"),
        ("twice_monthly", "Twice a month"),
        ("monthly", "Monthly"),
        ("irregular", "Irregular"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount per paycheck", text: $paycheckAmount)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Amount per paycheck")
                    Picker("Frequency", selection: $payFrequency) {
                        ForEach(frequencies, id: \.0) { freq in
                            Text(freq.1).tag(freq.0)
                        }
                    }
                    TextField("Source (e.g. ADP, employer name)", text: $paycheckName)
                        .accessibilityLabel("Paycheck source name")
                } header: {
                    Text("Paycheck")
                } footer: {
                    Text("Leave amount blank if you don't receive a paycheck.")
                        .font(.caption)
                }

                Section {
                    Toggle("I receive SSI", isOn: $receivesSSI)
                    if receivesSSI {
                        TextField("Monthly SSI amount", text: $ssiAmount)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Monthly SSI amount")
                    }
                } header: {
                    Text("SSI")
                } footer: {
                    Text("Turning this on unlocks the SSI monitor on the Budget tab.")
                        .font(.caption)
                }

                Section {
                    Toggle("I receive SSDI", isOn: $receivesSSDI)
                    if receivesSSDI {
                        TextField("Monthly SSDI amount", text: $ssdiAmount)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Monthly SSDI amount")
                    }
                } header: {
                    Text("SSDI")
                }

                if let err = saveError {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: seedFromOverview)
        }
    }

    // MARK: - Actions

    private func seedFromOverview() {
        guard let sources = dataManager.overview?.monthlyIncome.sources else { return }

        if let cents = sources.paycheck.amountCents, cents > 0 {
            paycheckAmount = String(format: "%.2f", Double(cents) / 100.0)
        }
        if let freq = sources.paycheck.frequency { payFrequency = freq }
        if let name = sources.paycheck.name { paycheckName = name }

        receivesSSI = sources.ssi.enabled
        if let cents = sources.ssi.amountCents, cents > 0 {
            ssiAmount = String(format: "%.2f", Double(cents) / 100.0)
        }
        receivesSSDI = sources.ssdi.enabled
        if let cents = sources.ssdi.amountCents, cents > 0 {
            ssdiAmount = String(format: "%.2f", Double(cents) / 100.0)
        }
    }

    private func save() {
        isSaving = true
        saveError = nil
        let update = buildUpdate()
        Task {
            do {
                try await dataManager.saveMonthlyIncome(update)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                saveError = "Couldn't save: \(error.localizedDescription)"
            }
        }
    }

    private func buildUpdate() -> MonthlyIncomeUpdate {
        var update = MonthlyIncomeUpdate()
        update.paycheckAmount = Double(paycheckAmount) ?? 0.0
        update.payFrequency = payFrequency
        update.paycheckName = paycheckName.isEmpty ? nil : paycheckName
        update.receivesSsi = receivesSSI
        update.receivesSsdi = receivesSSDI
        update.ssiAmount = receivesSSI ? (Double(ssiAmount) ?? 0.0) : nil
        update.ssdiAmount = receivesSSDI ? (Double(ssdiAmount) ?? 0.0) : nil
        return update
    }
}
