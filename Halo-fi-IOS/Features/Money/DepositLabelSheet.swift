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
//  A run-through, not a one-off: after each answer the next question loads
//  in place (from the queue the server sent, no round trip), until there
//  are none or the user taps Done for now. Saving never waits on the full
//  data refresh, which runs behind the sheet.
//

import SwiftUI

struct DepositLabelSheet: View {
    enum Mode: Equatable {
        /// Ask what the deposit is, then the gross if it is work income.
        case label(transactionId: String, source: String, amountCents: Int, occurredOn: String)
        /// The payer is known; only the gross is missing.
        case gross(labelId: String, employer: String, netCents: Int, lastGrossCents: Int?, occurredOn: String)
    }

    var onDone: (() -> Void)? = nil
    /// The card this started from, when the sheet should continue with
    /// the next learning question afterwards.
    private let startCard: AttentionCard?

    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(BankDataManager.self) private var bankDataManager
    @Environment(UserManager.self) private var userManager
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var currentCard: AttentionCard?
    @State private var step: Step
    @State private var grossText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var answered = 0
    @State private var finished = false
    @AccessibilityFocusState private var focus: Focus?

    private enum Step { case kind, gross }
    private enum Focus: Hashable { case heading, error }

    init(mode: Mode, onDone: (() -> Void)? = nil) {
        self.onDone = onDone
        self.startCard = nil
        _mode = State(initialValue: mode)
        _currentCard = State(initialValue: nil)
        if case .gross = mode { _step = State(initialValue: .gross) } else { _step = State(initialValue: .kind) }
    }

    /// Start from an attention card and keep going through the queue.
    init(card: AttentionCard, onDone: (() -> Void)? = nil) {
        self.onDone = onDone
        self.startCard = card
        let mode = Self.mode(for: card)
        _mode = State(initialValue: mode)
        _currentCard = State(initialValue: card)
        if case .gross = mode { _step = State(initialValue: .gross) } else { _step = State(initialValue: .kind) }
    }

    static func mode(for card: AttentionCard) -> Mode {
        let p = card.payload
        if card.actionType == "enter_gross", let labelId = p.labelId {
            return .gross(labelId: labelId, employer: p.employer ?? p.source ?? "your employer", netCents: p.netCents ?? p.amountCents ?? 0,
                          lastGrossCents: p.lastGrossCents, occurredOn: p.occurredOn ?? "")
        }
        return .label(transactionId: p.transactionId ?? "", source: p.source ?? "a deposit", amountCents: p.amountCents ?? 0,
                      occurredOn: p.occurredOn ?? "")
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
                    if finished {
                        allDone
                    } else {
                    Text(step == .kind
                         ? "\(BudgetFormatter.cents(amountCents)) from \(source), \(Self.spokenDate(occurredOn)). What is this?"
                         : "Paycheck from \(source), \(BudgetFormatter.cents(amountCents)) after taxes. What was the gross on the paystub?")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focus, equals: .heading)

                    if step == .kind {
                        details
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
                                .accessibilityHint(kind == .workIncome
                                                   ? "Opens one more question: the gross on the paystub."
                                                   : "Saves it and loads the next deposit, if there is one.")
                                .accessibilityIdentifier("depositKind-\(kind.rawValue)")
                            }
                        }
                    } else {
                        Text(userManager.capabilities.expenseType == .bwe
                             ? "The gross is the amount before taxes, on the paystub. Social Security counts gross wages, and the taxes withheld count as a Blind Work Expense."
                             : userManager.capabilities.showsBenefitsLane
                                ? "The gross is the amount before taxes, on the paystub. Social Security counts gross wages."
                                : "The gross is the amount before taxes, on the paystub.")
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
                            .accessibilityHint("Saves that gross and loads the next deposit, if there is one.")
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
                }
                .padding(20)
                .readableContentWidth()
            }
            .background(Color.haloBackground.ignoresSafeArea())
            .navigationTitle(finished ? "All caught up" : (step == .kind ? "This deposit" : "Paystub gross"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseToolbarButton(label: "Done for now", hint: answered == 0
                        ? "Closes without saving. The question stays on the Money tab."
                        : "Keeps what you answered and closes. The rest stay on the Money tab.") { dismiss() }
                }
            }
            .accessibilityAction(.escape) { dismiss() }
            .interactiveDismissDisabled(isSaving)
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .heading } }
            .onChange(of: step) { old, new in
                // Kind → gross within one deposit moves focus at once; a new
                // deposit's focus is scheduled by advance() after its announcement.
                if old == .kind && new == .gross { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .heading } }
            }
        }
    }

    /// What the bank actually said about this deposit — the account it
    /// landed in, the raw description, whether the payer sent more.
    @ViewBuilder
    private var details: some View {
        let p = currentCard?.payload
        let account = p?.accountId.flatMap { bankDataManager.accountLabel(for: $0) }
        let raw = p?.rawName
        let same = p?.sameSourceCount ?? 0
        let rows: [(String, String)] = [
            ("Into", account ?? "one of your accounts"),
            ("Bank description", (raw?.isEmpty == false && raw != source) ? raw! : source),
            ("From this payer", same > 1 ? "\(same) deposits in the last 30 days" : "first one in the last 30 days"),
        ] + ((p?.pending ?? false) ? [("Status", "Pending")] : [])
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.0).font(.caption).foregroundColor(.haloTextTertiary).frame(width: 110, alignment: .leading)
                    Text(row.1).font(.caption).foregroundColor(.haloTextSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var allDone: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(answered == 1 ? "All caught up. 1 deposit labeled." : "All caught up. \(answered) deposits labeled.")
                .font(.title2.weight(.bold))
                .foregroundColor(.haloTextPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focus, equals: .heading)
            Text("HaloFi remembers each payer. New deposits from them only ask what changed.")
                .font(.subheadline).foregroundColor(.haloTextSecondary)
            Button { onDone?(); dismiss() } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Closes this and returns to Money.")
        }
    }

    /// After a save: load the next question in place, or finish.
    private func advance(announcing saved: String) {
        answered += 1
        guard let card = currentCard, let next = dataManager.nextLearnCard(after: card) else {
            if startCard == nil {
                UIAccessibility.post(notification: .announcement, argument: saved)
                onDone?()
                dismiss()
            } else {
                finished = true
                UIAccessibility.post(notification: .announcement, argument: "\(saved) That was the last one.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { focus = .heading }
            }
            return
        }
        currentCard = next
        mode = Self.mode(for: next)
        grossText = ""
        errorMessage = nil
        step = { if case .gross = mode { return .gross } else { return .kind } }()
        // Say what was saved; the heading (which names the next question)
        // takes focus after the announcement instead of cutting it off.
        UIAccessibility.post(notification: .announcement, argument: saved)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { focus = .heading }
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
                advance(announcing: "Saved. \(src) is \(kind.title.lowercased()).")
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
                advance(announcing: taxes > 0 ? "Saved. Gross \(VoiceOverFormatter.dollarsAndCents(cents)), \(VoiceOverFormatter.dollarsAndCents(taxes)) withheld." : "Saved.")
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
