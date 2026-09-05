//
//  WorkExpensesView.swift
//  Halo-fi-IOS
//
//  The Work expenses screen (WP4), grown from BudgetView's deduction cards:
//  month header, candidates awaiting confirm, the logged list (with receipt
//  states and rotor actions), and the Log button. Receives receipts from
//  the share extension and "Mark as work expense" drafts from the Money tab.
//

import SwiftUI

struct WorkExpensesView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(UserManager.self) private var userManager
    @Environment(\.openURL) private var openURL

    @State private var showingLogSheet = false
    @State private var handoffReceipt: CapturedReceipt?
    @State private var handoffDraft: WorkExpenseDraft?
    @State private var receiptAttachTarget: SSIManualDeduction?
    /// WP6 — attach a receipt from a reminder (manual entry or bank charge).
    @State private var reminderAttachTarget: SSIReminder?

    private var monthName: String {
        DateFormatter().monthSymbols[Calendar.current.component(.month, from: Date()) - 1]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                logButtons
                if !receiptReminders.isEmpty {
                    ReceiptRemindersCard(reminders: receiptReminders) { reminder in
                        reminderAttachTarget = reminder
                    }
                }
                reviewButton
                if !dataManager.ssiCandidates.isEmpty {
                    SSIDeductionCandidatesCard(
                        candidates: dataManager.ssiCandidates,
                        onConfirm: { candidate, type in
                            try await dataManager.confirmSSIDeduction(candidate: candidate, as: type)
                        }
                    )
                }
                SSILoggedDeductionsCard(
                    deductions: dataManager.ssiManualDeductions,
                    totalsCents: dataManager.ssiManualTotalsCents,
                    expenseType: userManager.capabilities.expenseType,
                    onAdd: { showingLogSheet = true },
                    onDelete: { entry in
                        do { try await dataManager.deleteManualDeduction(entry.id) } catch {}
                    },
                    onAttachReceipt: { entry in receiptAttachTarget = entry },
                    onChangeType: { entry, type in
                        do {
                            try await dataManager.updateDeductionType(entry.id, to: type)
                        } catch {
                            UIAccessibility.post(notification: .announcement, argument: "Couldn't change the type. \(error.localizedDescription)")
                        }
                    },
                    onViewReceipt: { entry in
                        guard let assetId = entry.receiptAssetId else { return }
                        Task {
                            if let url = try? await ReceiptService.shared.viewURL(assetId: assetId) {
                                InAppBrowser.open(url)
                            } else {
                                UIAccessibility.post(notification: .announcement, argument: "Couldn't open the receipt right now.")
                            }
                        }
                    },
                    onExport: {
                        let now = Date(); let cal = Calendar.current
                        return try await dataManager.exportDeductionsCSVToTempFile(
                            year: cal.component(.year, from: now), month: cal.component(.month, from: now))
                    },
                    onEmailExport: { recipient in
                        let now = Date(); let cal = Calendar.current
                        return try await dataManager.emailDeductionsCSV(
                            year: cal.component(.year, from: now), month: cal.component(.month, from: now), to: recipient)
                    },
                    accountEmail: userManager.currentUser?.email
                )
                Text(ScreenReaderSummaryHeader.disclaimer)
                    .font(.caption).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { InAppBrowser.open(ProfileExplainer.wipaURL) } label: {
                    Label("Talk to a free benefits counselor", systemImage: "person.wave.2")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 100)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Work expenses")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await dataManager.refresh() }
        .sheet(isPresented: $showingLogSheet, onDismiss: { handoffReceipt = nil; handoffDraft = nil }) {
            SSILogManualDeductionView(
                capabilities: userManager.capabilities,
                initialReceipt: handoffReceipt,
                initialDraft: handoffDraft,
                onSave: { draft in
                    if let transactionId = draft.transactionId {
                        // Picked from the bank feed: log it against that
                        // charge, so it is matched and never double-counted.
                        try await dataManager.logTransactionDeduction(
                            transactionId: transactionId, type: draft.type, description: draft.description,
                            notes: draft.notes, receipt: draft.receipt)
                        return
                    }
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.dateFormat = "yyyy-MM-dd"
                    try await dataManager.logManualDeduction(
                        type: draft.type, amountCents: draft.amountCents, description: draft.description,
                        occurredOn: formatter.string(from: draft.occurredOn), notes: draft.notes, receipt: draft.receipt)
                }
            )
        }
        .sheet(item: $receiptAttachTarget) { entry in
            ReceiptCaptureView { captured in Task { await attachReceipt(captured, to: entry) } }
        }
        .sheet(item: $reminderAttachTarget) { reminder in
            ReceiptCaptureView { captured in Task { await attachReceipt(captured, for: reminder) } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .receiptShared)) { _ in takeHandoffs() }
        .onReceive(NotificationCenter.default.publisher(for: .workExpenseDraftRequested)) { _ in takeHandoffs() }
        .onAppear { takeHandoffs() }
    }

    private var header: some View {
        let count = dataManager.ssiManualDeductions.count
        let total = dataManager.ssiManualDeductions.reduce(0) { $0 + $1.amountCents }
        let impact = dataManager.ssiManualDeductions.reduce(0) { $0 + ($1.estimatedCheckImpactCents ?? 0) }
        let needs = dataManager.ssiManualDeductions.filter { $0.resolvedMatchStatus == "needs_receipt" }.count
        var detail = TabSummaries.expensesLine(count, total, impact)
        if needs > 0 { detail += " \(VoiceOverFormatter.count(needs, singular: "expense needs", plural: "expenses need")) a receipt." }
        if !dataManager.ssiCandidates.isEmpty {
            detail += " \(VoiceOverFormatter.count(dataManager.ssiCandidates.count, singular: "candidate", plural: "candidates")) waiting for your confirmation."
        }
        return ScreenReaderSummaryHeader(
            verdict: "\(monthName) work expenses",
            detail: detail,
            isEstimate: impact > 0,
            tone: needs > 0 ? .watch : .neutral
        )
    }

    private var receiptReminders: [SSIReminder] {
        dataManager.ssiReminders.filter(\.isReceiptReminder)
    }

    private var reviewButton: some View {
        let month = MonthKey.current
        let reviewDue = dataManager.ssiReminders.contains { $0.kind == "month_end_review" }
        return NavigationLink(value: BenefitsHomeView.Route.monthEndReview(month)) {
            Label(reviewDue ? "Review this month's expenses (due now)" : "Review this month's expenses", systemImage: "checklist")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Goes through each expense one at a time. Keep or remove; the running total is read after every step.")
    }

    /// One way in (Liam, 2026-09-05): the form, which can pull the charge
    /// from your transactions or read a receipt. Voice logging lives on
    /// the Agent tab as the "Log a work expense" shortcut.
    private var logButtons: some View {
        Button { showingLogSheet = true } label: {
            Label("Log an expense", systemImage: "plus.circle.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Opens the form. Pick the charge from your transactions, or add a receipt photo and Halo reads it.")
    }

    private func takeHandoffs() {
        if let receipt = ReceiptHandoff.shared.take() {
            handoffReceipt = receipt
            showingLogSheet = true
            UIAccessibility.post(notification: .announcement, argument: "Receipt received. Opening the work expense form.")
        } else if let draft = WorkExpenseHandoff.shared.take() {
            handoffDraft = draft
            showingLogSheet = true
            UIAccessibility.post(notification: .announcement, argument: "Logging \(draft.description) as a work expense. Confirm or edit.")
        }
    }

    private func attachReceipt(_ captured: CapturedReceipt, for reminder: SSIReminder) async {
        do {
            let uploaded = try await ReceiptService.shared.upload(captured)
            if let deductionId = reminder.deductionId {
                try await dataManager.attachReceipt(to: deductionId, assetId: uploaded.assetId)
            } else if let exclusionId = reminder.exclusionId {
                try await dataManager.attachReceipt(toExclusion: exclusionId, assetId: uploaded.assetId)
            }
            Haptics.success()
            UIAccessibility.post(notification: .announcement, argument: "Receipt attached for \(reminder.vendor ?? "the expense").")
        } catch {
            Haptics.error()
            UIAccessibility.post(notification: .announcement, argument: "Couldn't attach the receipt. \(error.localizedDescription)")
        }
    }

    private func attachReceipt(_ captured: CapturedReceipt, to entry: SSIManualDeduction) async {
        do {
            let uploaded = try await ReceiptService.shared.upload(captured)
            try await dataManager.attachReceipt(to: entry.id, assetId: uploaded.assetId)
            Haptics.success()
            UIAccessibility.post(notification: .announcement, argument: "Receipt attached to \(entry.description).")
        } catch {
            Haptics.error()
            UIAccessibility.post(notification: .announcement, argument: "Couldn't attach the receipt. \(error.localizedDescription)")
        }
    }
}
