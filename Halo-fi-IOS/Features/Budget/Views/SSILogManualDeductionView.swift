//
//  SSILogManualDeductionView.swift
//  Halo-fi-IOS
//
//  Phase 8 — sheet for adding a manual SSI deduction via UI (voice
//  path goes through the agent's add_ssi_deduction tool instead).
//  Mirrors SSIDeductionConfirmView's structure for visual parity.
//
//  Type defaulting follows the rules engine §4.1: blind users get
//  BWE by default, non-blind get IRWE. The user can override.
//

import SwiftUI

struct SSILogManualDeductionView: View {
    let isBlind: Bool

    /// Called with the values the user submitted. Caller writes to
    /// the API, refreshes the budget data, and dismisses on
    /// success. Throws are surfaced as inline errorMessage state.
    let onSave: (SSIExclusionType, Int, String, Date, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String = ""
    @State private var description: String = ""
    @State private var selectedType: SSIExclusionType
    @State private var occurredOn: Date = Date()
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        isBlind: Bool,
        onSave: @escaping (SSIExclusionType, Int, String, Date, String?) async throws -> Void
    ) {
        self.isBlind = isBlind
        self.onSave = onSave
        _selectedType = State(
            initialValue: isBlind ? .bwe : .irwe
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Amount in dollars")
                    TextField("Description (e.g. Uber to work)", text: $description)
                        .accessibilityLabel("Description of the expense")
                } header: {
                    Text("Expense").textCase(nil)
                }

                Section {
                    Picker("Type", selection: $selectedType) {
                        ForEach(SSIExclusionType.allCases, id: \.self) { type in
                            Text(label(for: type)).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint(typeHint)
                } header: {
                    Text("Type").textCase(nil)
                } footer: {
                    Text(typeFooter)
                }

                Section {
                    DatePicker(
                        "Date of expense",
                        selection: $occurredOn,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                } header: {
                    Text("When").textCase(nil)
                } footer: {
                    Text("Cannot be more than 90 days ago. SSA reporting is monthly.")
                }

                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: false)
                } header: {
                    Text("Notes").textCase(nil)
                } footer: {
                    Text("Keep your receipt — SSA may ask to verify.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Log deduction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving…" : "Save") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || !canSubmit)
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard let cents = parsedAmountCents, cents > 0 else { return false }
        return !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var parsedAmountCents: Int? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard let dollars = Double(trimmed), dollars > 0 else { return nil }
        return Int((dollars * 100).rounded())
    }

    private func label(for type: SSIExclusionType) -> String {
        switch type {
        case .bwe: return "BWE"
        case .irwe: return "IRWE"
        case .burial: return "Burial"
        }
    }

    private var typeFooter: String {
        switch selectedType {
        case .bwe:
            return "Blind Work Expense — $1 of SSI preserved per $1 spent. Statutorily blind users only."
        case .irwe:
            return "Impairment-Related Work Expense — about $0.50 of SSI preserved per $1 spent."
        case .burial:
            return "Designated burial-fund deposit — excluded from countable resources up to $1,500."
        }
    }

    private var typeHint: String {
        if isBlind {
            return "Default for blind users is BWE (worth twice as much per dollar as IRWE). Switch to IRWE for medical expenses unrelated to enabling work."
        }
        return "Default is IRWE. Burial covers designated burial-fund deposits."
    }

    private func submit() async {
        guard let cents = parsedAmountCents else { return }
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let notesOrNil: String? = trimmedNotes.isEmpty ? nil : trimmedNotes

        isSubmitting = true
        errorMessage = nil
        do {
            try await onSave(selectedType, cents, trimmedDesc, occurredOn, notesOrNil)
            // Track C — success haptic; sheet auto-dismisses next.
            Haptics.success()
            isSubmitting = false
            dismiss()
        } catch {
            // Track C — error haptic so the user feels the failure
            // even if VoiceOver hasn't announced the inline message.
            Haptics.error()
            isSubmitting = false
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
