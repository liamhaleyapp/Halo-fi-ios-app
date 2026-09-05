//
//  IncomeSourceEditorSheet.swift
//  Halo-fi-IOS
//
//  Edit what HaloFi knows about a payer (Liam, 2026-09-05): what it is,
//  the name, how often it pays, and the expected gross and take-home.
//  A payer with a cadence and a take-home becomes the budget's paycheck
//  line, so this replaces the old "amount per paycheck" fields.
//

import SwiftUI

struct IncomeSourceEditorSheet: View {
    let source: IncomeSource

    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    @State private var kind: IncomeKind
    @State private var employer: String
    @State private var cadence: Int   // 0 = irregular
    @State private var grossText: String
    @State private var netText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmForget = false

    private static let cadences: [(Int, String)] = [(7, "Every week"), (14, "Every 2 weeks"), (15, "Twice a month"), (30, "Monthly"), (0, "Irregular")]

    init(source: IncomeSource) {
        self.source = source
        let stored = IncomeKind(rawValue: source.kind) ?? .other
        _kind = State(initialValue: stored == .unsure ? .other : stored)
        _employer = State(initialValue: source.employer ?? source.sourceKey.capitalized)
        _cadence = State(initialValue: source.cadenceDays.map { d in [7, 14, 15].contains(d) ? d : (d >= 28 ? 30 : d) } ?? 0)
        _grossText = State(initialValue: source.lastGrossCents.map { String(format: "%.2f", Double($0) / 100) } ?? "")
        _netText = State(initialValue: source.lastNetCents.map { String(format: "%.2f", Double($0) / 100) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("What is it", selection: $kind) {
                        ForEach(IncomeKind.allCases.filter { $0 != .unsure }, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Name", text: $employer)
                        .accessibilityLabel("Payer name")
                } footer: {
                    Text("Deposits from this payer get this answer automatically.")
                }

                if kind == .workIncome {
                    Section {
                        Picker("How often you're paid", selection: $cadence) {
                            ForEach(Self.cadences, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        TextField("Expected gross per paycheck", text: $grossText).keyboardType(.decimalPad)
                            .accessibilityLabel("Expected gross per paycheck, in dollars")
                        TextField("Expected take-home per paycheck", text: $netText).keyboardType(.decimalPad)
                            .accessibilityLabel("Expected take-home per paycheck, in dollars")
                    } header: {
                        Text("Pay")
                    } footer: {
                        Text("Take-home times paychecks per month becomes your budget's income. Each real paycheck still asks for its paystub gross, because hours change. Estimate.")
                    }
                }

                Section {
                    Button(role: .destructive) { confirmForget = true } label: {
                        Label("Forget this payer", systemImage: "trash").frame(minHeight: 44)
                    }
                    .accessibilityHint("HaloFi will ask again the next time this payer sends money. Answers you already gave stay.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(source.employer ?? "Payer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { CloseToolbarButton(label: "Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }.disabled(isSaving)
                }
            }
            .confirmationDialog("Forget \(source.employer ?? "this payer")?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { forget() }
                Button("Keep", role: .cancel) {}
            }
            .accessibilityAction(.escape) { dismiss() }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        var update = IncomeSourceUpdate()
        update.kind = kind.rawValue
        update.employer = employer.trimmingCharacters(in: .whitespaces)
        if kind == .workIncome {
            if cadence == 0 { update.clear_cadence = true } else { update.cadence_days = cadence }
            update.expected_gross_cents = DepositLabelSheet.cents(from: grossText)
            update.expected_net_cents = DepositLabelSheet.cents(from: netText)
        }
        Task {
            do {
                try await dataManager.updateSource(key: source.sourceKey, update: update)
                isSaving = false
                Haptics.success()
                UIAccessibility.post(notification: .announcement, argument: "Saved.")
                dismiss()
            } catch {
                isSaving = false
                errorMessage = "Couldn't save. \(error.localizedDescription)"
                UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
            }
        }
    }

    private func forget() {
        isSaving = true
        Task {
            do {
                try await dataManager.forgetSource(key: source.sourceKey)
                isSaving = false
                UIAccessibility.post(notification: .announcement, argument: "Forgotten.")
                dismiss()
            } catch {
                isSaving = false
                errorMessage = "Couldn't forget it. \(error.localizedDescription)"
            }
        }
    }
}
