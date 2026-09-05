//
//  IncomeEditorView.swift
//  Halo-fi-IOS
//
//  Sheet presented from BudgetView for editing the user's monthly
//  income sources (paycheck, SSI amount, SSDI amount) and the two SSI
//  resource figures (ABLE balance, burial fund).
//
//  WHICH benefits the user receives, and whether they are statutorily
//  blind, are no longer toggles here — they come from the benefits
//  profile (Settings → Benefits profile), which is what the capabilities
//  object is computed from. This sheet only edits amounts.
//

import SwiftUI

struct IncomeEditorView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(UserManager.self) private var userManager
    @Environment(\.dismiss) private var dismiss

    // Paycheck
    @State private var paycheckAmount: String = ""
    @State private var payFrequency: String = "biweekly"
    @State private var paycheckName: String = ""

    // Benefit amounts (shown per capabilities)
    @State private var ssiAmount: String = ""
    @State private var ssdiAmount: String = ""

    // SSI resource figures
    @State private var ableBalanceDollars: String = ""
    @State private var burialFundDollars: String = ""

    @State private var isSaving = false
    @State private var saveError: String?

    private let frequencies = [
        ("weekly", "Weekly"),
        ("biweekly", "Every two weeks"),
        ("twice_monthly", "Twice a month"),
        ("monthly", "Monthly"),
        ("irregular", "Irregular"),
    ]

    private var showsSSI: Bool { userManager.capabilities.showsResourceCounter }
    private var showsSSDI: Bool { userManager.capabilities.showsSSDILane }
    private var hasABLE: Bool { userManager.benefitsProfile.hasAbleAccount ?? false }

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
                    .accessibilityHint("Sets how often your paycheck arrives so we can calculate your monthly income.")
                    TextField("Source (e.g. ADP, employer name)", text: $paycheckName)
                        .accessibilityLabel("Paycheck source name")
                } header: {
                    Text("Paycheck")
                } footer: {
                    Text("Leave amount blank if you don't receive a paycheck.")
                        .font(.caption)
                }

                if showsSSI || showsSSDI {
                    Section {
                        if showsSSI {
                            TextField("Monthly SSI amount", text: $ssiAmount)
                                .keyboardType(.decimalPad)
                                .accessibilityLabel("Monthly SSI amount")
                        }
                        if showsSSDI {
                            TextField("Monthly SSDI amount", text: $ssdiAmount)
                                .keyboardType(.decimalPad)
                                .accessibilityLabel("Monthly SSDI amount")
                        }
                    } header: {
                        Text("Benefits")
                    } footer: {
                        Text("To change which benefits you receive, go to Settings, then Benefits profile.")
                            .font(.caption)
                    }
                }

                if showsSSI {
                    Section {
                        if hasABLE {
                            TextField("ABLE account balance", text: $ableBalanceDollars)
                                .keyboardType(.decimalPad)
                                .accessibilityLabel("ABLE account balance in dollars")
                        }
                        TextField("Designated burial fund (max $1,500)", text: $burialFundDollars)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Designated burial fund balance in dollars, up to $1,500")
                    } header: {
                        Text("SSI resources")
                    } footer: {
                        Text("Estimate. ABLE balances above $100,000 and burial funds above $1,500 still count toward the resource limit. Whether you have an ABLE account is set in Settings, then Benefits profile.")
                            .font(.caption)
                    }
                }

                if let err = saveError {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseToolbarButton(label: "Cancel") { dismiss() }
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
        guard let overview = dataManager.overview else { return }
        let sources = overview.monthlyIncome.sources

        if let cents = sources.paycheck.amountCents, cents > 0 {
            paycheckAmount = String(format: "%.2f", Double(cents) / 100.0)
        }
        if let freq = sources.paycheck.frequency { payFrequency = freq }
        if let name = sources.paycheck.name { paycheckName = name }

        if let cents = sources.ssi.amountCents, cents > 0 {
            ssiAmount = String(format: "%.2f", Double(cents) / 100.0)
        }
        if let cents = sources.ssdi.amountCents, cents > 0 {
            ssdiAmount = String(format: "%.2f", Double(cents) / 100.0)
        }

        if let profile = overview.ssiProfile {
            if let cents = profile.ableBalanceCents, cents > 0 {
                ableBalanceDollars = String(format: "%.2f", Double(cents) / 100.0)
            }
            if let cents = profile.burialFundCents, cents > 0 {
                burialFundDollars = String(format: "%.2f", Double(cents) / 100.0)
            }
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
        if showsSSI {
            update.ssiAmount = Double(ssiAmount) ?? 0.0
            update.ableBalanceCents = hasABLE
                ? IncomeEditorView.dollarsToCents(ableBalanceDollars)
                : 0
            update.burialFundCents = IncomeEditorView.dollarsToCents(burialFundDollars)
        }
        if showsSSDI {
            update.ssdiAmount = Double(ssdiAmount) ?? 0.0
        }
        return update
    }

    /// Convert a free-text dollar string ("12.50") to integer cents.
    /// Returns 0 for blank / unparseable input so we never send nil
    /// to the backend (the engine treats nil as "unset"; we want
    /// blank to mean "$0 designated").
    private static func dollarsToCents(_ raw: String) -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let dollars = Double(trimmed) else { return 0 }
        return Int((dollars * 100).rounded())
    }
}
