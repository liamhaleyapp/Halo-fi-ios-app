//
//  DepositLabelSheet.swift
//  Halo-fi-IOS
//
//  One question about a deposit (Liam, 2026-09-05): "$412 from ACME
//  PAYROLL, September 3. What is this?" Six big buttons. Work income asks a
//  second question — the gross on the paystub — every pay period, because
//  hours vary; "Same as last time" is one tap when the payer is known.
//  Benefit / transfer / refund / gift / not sure save at once.
//

import SwiftUI

struct DepositLabelSheet: View {
    enum Mode: Equatable {
        /// Ask what the deposit is, then the gross if it is work income.
        case label(transactionId: String, source: String, amountCents: Int, occurredOn: String)
        /// The payer is known; only the gross is missing.
        case gross(labelId: String, employer: String, netCents: Int, lastGrossCents: Int?, occurredOn: String)
    }

    let mode: Mode
    var onDone: (() -> Void)? = nil

    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var grossText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var focus: Focus?

    private enum Step { case kind, gross }
    private enum Focus: Hashable { case heading, error }

    init(mode: Mode, onDone: (() -> Void)? = nil) {
        self.mode = mode
        self.onDone = onDone
        if case .gross = mode { _step = State(initialValue: .gross) } else { _step = State(initialValue: .kind) }
    }

    private var amountCents: Int {
        switch mode {
        case .label(_, _, let cents, _): return cents
        case .gross(_, _, let net, _, _): return net
        }
    }

    private var source: String {
        switch mode {
        case .label(_, let s, _, _): return s
        case .gross(_, let e, _, _, _): return e
        }
    }

    private var occurredOn: String {
        switch mode {
        case .label(_, _, _, let d): return d
        case .gross(_, _, _, _, let d): return d
        }
    }

    private var lastGross: Int? {
        if case .gross(_, _, _, let last, _) = mode { return last }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(step == .kind
                         ? "\(BudgetFormatter.cents(amountCents)) from \(source), \(Self.spokenDate(occurredOn)). What is this?"
                         : "Paycheck from \(source), \(BudgetFormatter.cents(amountCents)) after taxes. What was the gross on the paystub?")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focus, equals: .heading)

                    if step == .kind {
                        Text("One tap. HaloFi remembers this payer, so next time it only asks what changed.")
                            .font(.subheadline).foregroundColor(.haloTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 10) {
                            ForEach(IncomeKind.allCases, id: \.self) { kind in
                                Button { choose(kind) } label: {
                                    Label(kind.title, systemImage: kind.icon)
                                        .font(.body.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .background(Color.haloSecondaryBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(HapticPlainButtonStyle())
                                .disabled(isSaving)
                                .accessibilityIdentifier("depositKind-\(kind.rawValue)")
                            }
                        }
                    } else {
                        Text("The gross is the amount before taxes, on the paystub. Social Security counts gross wages, and the taxes withheld can count as a work expense.")
                            .font(.subheadline).foregroundColor(.haloTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let last = lastGross {
                            Button { saveGross(last) } label: {
                                Label("Same as last time, \(BudgetFormatter.cents(last))", systemImage: "arrow.counterclockwise")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 56)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSaving)
                        }
                        HStack {
                            Text("$").font(.title2)
                            TextField("Gross amount", text: $grossText)
                                .keyboardType(.decimalPad)
                                .font(.title2)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Gross amount in dollars")
                        }
                        Button {
                            guard let cents = Self.cents(from: grossText) else {
                                errorMessage = "Enter the gross amount as dollars and cents, like 640.00."
                                UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
                                return
                            }
                            saveGross(cents)
                        } label: {
                            Text(isSaving ? "Saving…" : "Save gross")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                        Button {
                            if case .label = mode { saveKind(.workIncome, gross: nil) } else { dismiss() }
                        } label: {
                            Text("I don't have the paystub right now")
                                .font(.subheadline).foregroundColor(.haloTextSecondary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(isSaving)
                        .accessibilityHint("Saves it as work income at the deposit amount for now. HaloFi asks again for the gross.")
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.callout).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($focus, equals: .error)
                    }
                }
                .padding(20)
                .readableContentWidth()
            }
            .background(Color.haloBackground.ignoresSafeArea())
            .navigationTitle(step == .kind ? "This deposit" : "Paystub gross")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseToolbarButton(hint: "Closes without saving. The question stays on the Money tab.") { dismiss() }
                }
            }
            .accessibilityAction(.escape) { dismiss() }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .heading } }
            .onChange(of: step) { _, _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .heading } }
        }
    }

    // MARK: - Actions

    private func choose(_ kind: IncomeKind) {
        Haptics.engine.play(.tapLight)
        if kind == .workIncome {
            step = .gross
        } else {
            saveKind(kind, gross: nil)
        }
    }

    private func saveKind(_ kind: IncomeKind, gross: Int?) {
        guard case .label(let txn, let src, _, _) = mode else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await dataManager.labelDeposit(transactionId: txn, kind: kind, grossCents: gross, employer: kind == .workIncome ? src : nil)
                isSaving = false
                Haptics.success()
                UIAccessibility.post(notification: .announcement, argument: "Saved. \(src) is \(kind.title.lowercased()).")
                onDone?()
                dismiss()
            } catch {
                isSaving = false
                fail(error)
            }
        }
    }

    private func saveGross(_ cents: Int) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                switch mode {
                case .label(let txn, let src, _, _):
                    try await dataManager.labelDeposit(transactionId: txn, kind: .workIncome, grossCents: cents, employer: src)
                case .gross(let labelId, _, _, _, _):
                    try await dataManager.enterGross(labelId: labelId, grossCents: cents)
                }
                isSaving = false
                Haptics.success()
                let taxes = max(0, cents - amountCents)
                UIAccessibility.post(notification: .announcement,
                                     argument: taxes > 0 ? "Saved. Gross \(VoiceOverFormatter.dollarsAndCents(cents)), \(VoiceOverFormatter.dollarsAndCents(taxes)) withheld." : "Saved.")
                onDone?()
                dismiss()
            } catch {
                isSaving = false
                fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        Haptics.error()
        errorMessage = "Couldn't save that. \(error.localizedDescription)"
        UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .error }
    }

    static func cents(from text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return Int((value * 100).rounded())
    }

    static func spokenDate(_ iso: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMMM d"; return out.string(from: d)
    }
}
