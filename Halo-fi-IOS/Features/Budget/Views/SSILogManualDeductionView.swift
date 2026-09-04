//
//  SSILogManualDeductionView.swift
//  Halo-fi-IOS
//
//  Phase 8 — sheet for adding a manual SSI deduction via UI (voice
//  path goes through the agent's add_ssi_deduction tool instead).
//  Mirrors SSIDeductionConfirmView's structure for visual parity.
//
//  Type defaulting comes from the capabilities object: BWE only when
//  Social Security's record confirms statutory blindness, IRWE
//  otherwise. When `bweLocked`, the BWE choice is visible but disabled
//  and the footer explains the BPQY unlock path (hard rule 4).
//

import SwiftUI

struct SSILogManualDeductionView: View {
    let capabilities: UserCapabilities

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
        capabilities: UserCapabilities,
        onSave: @escaping (SSIExclusionType, Int, String, Date, String?) async throws -> Void
    ) {
        self.capabilities = capabilities
        self.onSave = onSave
        _selectedType = State(
            initialValue: capabilities.expenseType == .bwe ? .bwe : .irwe
        )
    }

    private var bweLocked: Bool { capabilities.bweLocked }

    var body: some View {
        NavigationStack {
            Form {
                // Voice intake lives at a higher entry point — the
                // top-of-Budget "Log expense" quick action goes
                // directly to the conversation. This sheet is the
                // typed-form fallback reachable from the "Add"
                // button on the Logged Deductions card.
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
                    .onChange(of: selectedType) { _, newValue in
                        // Visible but locked: never compute BWE for an
                        // unverified user. Snap back and say why.
                        if newValue == .bwe && bweLocked {
                            selectedType = .irwe
                            UIAccessibility.post(
                                notification: .announcement,
                                argument: "Blind Work Expenses are locked until Social Security's record confirms statutory blindness. Logged as an Impairment-Related Work Expense instead."
                            )
                        }
                    }
                } header: {
                    Text("Type").textCase(nil)
                } footer: {
                    Text(bweLocked
                         ? "Blind Work Expenses — locked until Social Security's record confirms statutory blindness. Check your award letter or BPQY, then update Settings, Benefits profile. Until then this is logged as IRWE."
                         : typeFooter)
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
        if capabilities.expenseType == .bwe {
            return "Default for statutorily blind users is BWE (worth twice as much per dollar as IRWE). Switch to IRWE for medical expenses unrelated to enabling work."
        }
        if bweLocked {
            return "BWE is locked until Social Security confirms statutory blindness. Default is IRWE. Burial covers designated burial-fund deposits."
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
            // VoiceOver announcement so blind users hear confirmation
            // before the sheet dismisses. Without this, a successful
            // save was tactile-only and they couldn't tell whether it
            // worked. Posting before dismiss is intentional —
            // VoiceOver flushes the announcement queue on view
            // teardown otherwise.
            UIAccessibility.post(
                notification: .announcement,
                argument: "Deduction saved."
            )
            isSubmitting = false
            dismiss()
        } catch {
            // Track C — error haptic so the user feels the failure
            // even if VoiceOver hasn't announced the inline message.
            Haptics.error()
            UIAccessibility.post(
                notification: .announcement,
                argument: "Couldn't save the deduction. \(error.localizedDescription)"
            )
            isSubmitting = false
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
