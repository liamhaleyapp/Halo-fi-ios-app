//
//  BudgetDataManager.swift
//  Halo-fi-IOS
//
//  Observable store for the Budget view. Mirrors BankDataManager's
//  pattern: @Observable @MainActor with isLoading / error state and
//  an in-flight refresh guard.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class BudgetDataManager {
    // MARK: - State

    var overview: BudgetOverview?
    var isLoading = false
    var error: BudgetError?

    /// Last successful fetch — powers "Updated X ago" labels.
    private(set) var lastFetched: Date?

    /// SSI deduction candidates the backend classifier flagged this
    /// month. Empty when the user isn't on SSI or has no plausibly-
    /// deductible transactions. Refreshed alongside `overview`.
    var ssiCandidates: [SSIDeductionCandidate] = []

    /// Manual SSI deductions (voice- or UI-entered) for the current
    /// month. Phase 8 — distinct from candidates because these are
    /// already saved.
    var ssiManualDeductions: [SSIManualDeduction] = []
    var ssiManualTotalsCents: [String: Int] = [:]

    /// WP6 — reminders (hand in last month, receipts overdue, attach a
    /// receipt to a confirmed charge, month-end review) + the field-office
    /// guidance that rides along with them.
    var ssiReminders: [SSIReminder] = []
    var fieldOffice: FieldOfficeGuidance?

    /// "Needs your attention" (2026-09-05): the top cards for the Money tab
    /// and how many more the server holds. Learn cards resolve through
    /// `labelDeposit` / `enterGross` / `confirmSSIDeduction`.
    var attentionCards: [AttentionCard] = []
    var attentionQueue: [AttentionCard] = []
    var attentionMoreCount: Int = 0
    /// Bumped on every local resolve/dismiss. A refresh started before the
    /// bump must not put a resolved card back (2026-09-06 review).
    @ObservationIgnored private var attentionGeneration = 0
    @ObservationIgnored private var attentionRefreshPending = false

    /// This month's learned income (sources, gross by employer).
    var incomeSummary: IncomeSummary?

    /// Bills (2026-09-05): recurring outflow streams with the user's answers.
    var bills: RecurringResponse?

    // MARK: - Dependencies

    private let service: BudgetServiceProtocol
    private let ssiService: SSIServiceProtocol
    private var refreshTask: Task<Void, Never>?
    /// Annotations needed so deinit can read this without crossing
    /// the @Observable wrapper or MainActor isolation.
    @ObservationIgnored
    private nonisolated(unsafe) var mutationObserver: NSObjectProtocol?

    // MARK: - Tuning

    private static let freshnessWindow: TimeInterval = 30

    // MARK: - Init

    init(
        service: BudgetServiceProtocol = BudgetService.shared,
        ssiService: SSIServiceProtocol = SSIService.shared
    ) {
        self.service = service
        self.ssiService = ssiService

        mutationObserver = NotificationCenter.default.addObserver(
            forName: .budgetDataDidMutate,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // WP5 — scoped: the server says WHAT changed. The overview
            // depends on all three scopes (income block, SSI resources from
            // accounts, the budget itself), so any of them refreshes it;
            // the debounce collapses bursts. No more refresh-on-every-reply.
            let scope = (note.userInfo?["scope"] as? String) ?? "budget"
            Task { @MainActor [weak self] in
                Logger.info("BudgetDataManager: data mutated scope=\(scope)")
                self?.markStale()
                self?.scheduleDebouncedRefresh()
            }
        }
    }

    /// Debounce: several writes can land in one turn (income + budget), so
    /// wait for a quiet moment before hitting the API once.
    private var pendingMutationRefresh: Task<Void, Never>?

    private func scheduleDebouncedRefresh() {
        pendingMutationRefresh?.cancel()
        pendingMutationRefresh = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
            await self?.fetchSuggestion()
        }
    }

    // MARK: - WP5 suggestions + category editing

    /// Latest smart suggestion; nil until fetched or when there isn't
    /// enough history.
    var suggestion: BudgetSuggestion?

    func fetchSuggestion() async {
        if UITestArchetype.isActive { return }
        do {
            suggestion = try await service.fetchSuggestion()
        } catch {
            Logger.warning("BudgetDataManager: fetch suggestion failed: \(error)")
        }
    }

    func applySuggestion() async throws {
        do {
            try await service.applySuggestion()
        } catch {
            Logger.error("BudgetDataManager: apply suggestion failed: \(error)")
            throw error
        }
        await refresh()
        await fetchSuggestion()
        announceMonthlyTotal(prefix: "Budget created.")
    }

    func addCategory(code: String, limitAmount: Double) async throws {
        do {
            try await service.addCategory(code: code, limitAmount: limitAmount)
        } catch {
            Logger.error("BudgetDataManager: add category failed: \(error)")
            throw error
        }
        await refresh()
        announceMonthlyTotal(prefix: "Added \(BudgetFormatter.displayName(forCategory: code)).")
    }

    func deleteCategory(_ category: BudgetStatusCategory) async throws {
        guard let id = category.categoryId else { throw BudgetError(underlying: URLError(.badURL)) }
        do {
            try await service.deleteCategory(categoryId: id)
        } catch {
            Logger.error("BudgetDataManager: delete category failed: \(error)")
            throw error
        }
        await refresh()
        announceMonthlyTotal(prefix: "Removed \(BudgetFormatter.displayName(forCategory: category.category)).")
    }

    /// Every budget change ends with the new monthly total, spoken.
    func announceMonthlyTotal(prefix: String) {
        guard let total = overview?.budgetStatus.total else { return }
        let text = "\(prefix) New monthly total: \(VoiceOverFormatter.dollars(total.limitCents))."
        Haptics.engine.play(.tapLight)
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    deinit {
        if let mutationObserver {
            NotificationCenter.default.removeObserver(mutationObserver)
        }
    }

    // MARK: - API

    var shouldRefresh: Bool {
        guard let lastFetched else { return true }
        return Date().timeIntervalSince(lastFetched) >= Self.freshnessWindow
    }

    func markStale() {
        lastFetched = nil
    }

    /// Pull the latest overview. Coalesces concurrent calls so hitting
    /// refresh three times in a row doesn't fire three requests.
    func refresh(userTz: String? = TimeZone.current.identifier) async {
        if UITestArchetype.isActive { return }
        if let existing = refreshTask {
            await existing.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(userTz: userTz)
        }
        refreshTask = task
        await task.value
        refreshTask = nil
        if attentionRefreshPending {
            // A card was resolved while the last fetch was in flight; pull once more.
            attentionRefreshPending = false
            if let r = try? await AttentionService.shared.fetch(userTz: userTz) {
                attentionCards = r.cards
                attentionQueue = r.queue
                attentionMoreCount = r.moreCount
            }
        }
    }

    /// Save an income update and refresh the overview.
    /// Throws so the view can surface inline errors during editing.
    func saveMonthlyIncome(_ update: MonthlyIncomeUpdate) async throws {
        do {
            try await service.updateMonthlyIncome(update)
        } catch {
            Logger.error("BudgetDataManager: save income failed: \(error)")
            throw error
        }
        // Re-pull overview so totals and sources reflect the update.
        await refresh()
    }

    /// Update a single category's monthly limit, then refresh the overview
    /// so the new value flows through the budget-status pipeline (totals,
    /// pace classification, etc.) on the next view read.
    func saveCategoryLimit(categoryId: String, limitAmount: Double, announce: Bool = false) async throws {
        defer { if announce { announceMonthlyTotal(prefix: "Limit updated.") } }
        do {
            try await service.updateCategoryLimit(
                categoryId: categoryId,
                limitAmount: limitAmount
            )
        } catch {
            Logger.error("BudgetDataManager: save category limit failed: \(error)")
            throw error
        }
        await refresh()
    }

    // MARK: - Internal

    private func performRefresh(userTz: String?) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            overview = try await service.getOverview(userTz: userTz)
            lastFetched = Date()
        } catch {
            Logger.error("BudgetDataManager: fetch overview failed: \(error)")
            self.error = BudgetError(underlying: error)
        }

        // SSI candidates + manual deductions in parallel — independent
        // endpoints, failures isolated (a candidates failure must not tank
        // the Budget view).
        let ssi = ssiService
        async let candidatesResult: Result<SSICandidatesResponse, Error> = {
            do { return .success(try await ssi.fetchCandidates(userTz: userTz)) } catch { return .failure(error) }
        }()
        async let manualResult: Result<SSIManualDeductionsResponse, Error> = {
            do { return .success(try await ssi.fetchManualDeductions(userTz: userTz)) } catch { return .failure(error) }
        }()
        switch await candidatesResult {
        case .success(let response): ssiCandidates = response.candidates
        case .failure(let error):
            Logger.error("BudgetDataManager: fetch SSI candidates failed: \(error)")
            ssiCandidates = []
        }
        switch await manualResult {
        case .success(let response):
            ssiManualDeductions = response.deductions
            ssiManualTotalsCents = response.totalsCents
        case .failure(let error):
            Logger.error("BudgetDataManager: fetch manual deductions failed: \(error)")
            ssiManualDeductions = []
            ssiManualTotalsCents = [:]
        }

        // WP6 — reminders. Non-benefit users get an empty list. Local
        // notifications are scheduled from here (deduped by reminder id).
        do {
            let response = try await ssiService.fetchReminders(userTz: userTz)
            ssiReminders = response.reminders
            fieldOffice = response.fieldOffice
            await ReminderNotificationScheduler.shared.sync(response.reminders)
        } catch {
            Logger.error("BudgetDataManager: fetch reminders failed: \(error)")
            ssiReminders = []
        }

        // Attention + income summary, in parallel, failures isolated: the
        // stack keeps its last cards when the fetch fails.
        let generationAtStart = attentionGeneration
        async let attentionResult: Result<AttentionResponse, Error> = {
            do { return .success(try await AttentionService.shared.fetch(userTz: userTz)) } catch { return .failure(error) }
        }()
        async let incomeResult: Result<IncomeSummary, Error> = {
            do { return .success(try await IncomeService.shared.summary(month: nil)) } catch { return .failure(error) }
        }()
        async let billsResult: Result<RecurringResponse, Error> = {
            do { return .success(try await RecurringService.shared.bills()) } catch { return .failure(error) }
        }()
        switch await attentionResult {
        case .success(let response):
            if generationAtStart == attentionGeneration {
                attentionCards = response.cards
                attentionQueue = response.queue
                attentionMoreCount = response.moreCount
            } else {
                // Something was resolved while this was in flight: keep the
                // local state and fetch once more when this refresh ends.
                attentionRefreshPending = true
            }
        case .failure(let error):
            Logger.warning("BudgetDataManager: fetch attention failed: \(error)")
        }
        switch await incomeResult {
        case .success(let summary): incomeSummary = summary
        case .failure(let error): Logger.warning("BudgetDataManager: fetch income summary failed: \(error)")
        }
        switch await billsResult {
        case .success(let response): bills = response
        case .failure(let error): Logger.warning("BudgetDataManager: fetch bills failed: \(error)")
        }
    }

    /// Answer "is this a bill?" — instantly on the card, then refresh.
    func confirmBill(streamId: String, isBill: Bool, label: String? = nil, kind: String? = nil) async throws {
        _ = try await RecurringService.shared.confirm(streamId: streamId, isBill: isBill, label: label, kind: kind)
        if let card = (attentionCards + attentionQueue).first(where: { $0.kind == "bill_confirm" && $0.payload.streamId == streamId }) {
            resolveCard(card)
        } else {
            markStale()
            Task { await refresh() }
        }
    }

    // MARK: - Attention + income labels (2026-09-05)

    /// "Not now": hide the card for a week, locally at once and on the server.
    func dismissCard(_ card: AttentionCard, days: Int = 7) async {
        attentionGeneration += 1
        attentionCards.removeAll { $0.id == card.id }
        attentionQueue.removeAll { $0.id == card.id }
        do { try await AttentionService.shared.dismiss(cardId: card.id, days: days) } catch {
            Logger.warning("BudgetDataManager: dismiss failed: \(error)")
        }
        markStale()
        await refresh()
    }

    /// A card was resolved: drop it now, promote the next learning question
    /// from the queue so the stack never blanks, and refresh in the
    /// background (the full refresh recomputes the overview and takes
    /// seconds — nothing on screen waits for it).
    func resolveCard(_ card: AttentionCard, refresh: Bool = true) {
        attentionGeneration += 1
        attentionCards.removeAll { $0.id == card.id }
        attentionQueue.removeAll { $0.id == card.id }
        attentionQueue.removeAll { $0.id == card.id }
        // Same payer answered → its other deposits are labeled server-side.
        if card.kind == "deposit_label", let source = card.payload.source {
            attentionQueue.removeAll { $0.kind == "deposit_label" && $0.payload.source == source }
        }
        if attentionCards.count < 3, let next = attentionQueue.first(where: { q in !attentionCards.contains { $0.kind == q.kind } }) {
            attentionQueue.removeAll { $0.id == next.id }
            attentionCards.append(next)
        }
        markStale()
        if refresh { Task { await self.refresh() } }
    }

    /// The next learning question after `card`, for the sheet to continue
    /// with: gross questions first, then deposits.
    func nextLearnCard(after card: AttentionCard) -> AttentionCard? {
        let pool = (attentionQueue + attentionCards).filter { $0.id != card.id && ($0.kind == "deposit_label" || $0.kind == "wage_gross") }
        return pool.first { $0.kind == "wage_gross" } ?? pool.first
    }

    /// Say what a deposit was. Work income may carry the paystub gross.
    /// Returns as soon as the server has it; the refresh runs behind.
    @discardableResult
    func labelDeposit(transactionId: String, kind: IncomeKind, grossCents: Int?, employer: String?) async throws -> IncomeLabelView {
        let label = try await IncomeService.shared.label(transactionId: transactionId, kind: kind, grossCents: grossCents, employer: employer)
        if let card = (attentionCards + attentionQueue).first(where: { $0.payload.transactionId == transactionId }) {
            resolveCard(card)
        } else {
            markStale()
            Task { await refresh() }
        }
        return label
    }

    /// The paystub gross for a paycheck a rule already labeled.
    @discardableResult
    func enterGross(labelId: String, grossCents: Int) async throws -> IncomeLabelView {
        let label = try await IncomeService.shared.updateLabel(id: labelId, grossCents: grossCents)
        if let card = (attentionCards + attentionQueue).first(where: { $0.payload.labelId == labelId }) {
            resolveCard(card)
        } else {
            markStale()
            Task { await refresh() }
        }
        return label
    }

    func updateSource(key: String, update: IncomeSourceUpdate) async throws {
        _ = try await IncomeService.shared.updateSource(key: key, update: update)
        markStale()
        await refresh()
    }

    func forgetSource(key: String) async throws {
        try await IncomeService.shared.deleteSource(key: key)
        markStale()
        await refresh()
    }

    func forgetLabel(id: String) async throws {
        try await IncomeService.shared.deleteLabel(id: id)
        markStale()
        await refresh()
    }

    // MARK: - SSI deductions (Phase 3)

    /// Confirm a candidate as a BWE / IRWE / burial deduction and
    /// refresh both the overview (so projected SSI updates) and the
    /// candidates list (so the confirmed row drops off).
    func confirmSSIDeduction(
        candidate: SSIDeductionCandidate,
        as type: SSIExclusionType,
        notes: String? = nil
    ) async throws {
        let request = SSICreateExclusionRequest(
            transactionId: candidate.transactionId,
            exclusionType: type,
            description: candidate.description.isEmpty ? "Bank transaction" : candidate.description,
            notes: notes
        )
        do {
            _ = try await ssiService.confirm(request)
        } catch {
            Logger.error("BudgetDataManager: confirm SSI deduction failed: \(error)")
            throw error
        }
        await refresh()
    }

    /// Log an expense picked from the bank feed (the work-expense form's
    /// "Find it in your transactions"): the same exclusion path the
    /// candidate cards use, so the charge is matched and never counted
    /// twice.
    func logTransactionDeduction(
        transactionId: String,
        type: SSIExclusionType,
        description: String,
        notes: String? = nil,
        receipt: ManualDeductionReceiptFields = ManualDeductionReceiptFields()
    ) async throws {
        var request = SSICreateExclusionRequest(
            transactionId: transactionId,
            exclusionType: type,
            description: description.isEmpty ? "Bank transaction" : description,
            notes: notes
        )
        request.receiptAssetId = receipt.assetId
        request.receiptPending = receipt.pending
        request.counselorQuestion = receipt.counselorQuestion
        do {
            _ = try await ssiService.confirm(request)
        } catch {
            Logger.error("BudgetDataManager: log transaction deduction failed: \(error)")
            throw error
        }
        await refresh()
    }

    /// Log a manual deduction (Phase 8 — voice or UI entry). After
    /// success, refreshes the whole overview so projected SSI math
    /// reflects the new deduction.
    @discardableResult
    func logManualDeduction(
        type: SSIExclusionType,
        amountCents: Int,
        description: String,
        occurredOn: String? = nil,
        notes: String? = nil,
        receipt: ManualDeductionReceiptFields = ManualDeductionReceiptFields()
    ) async throws -> SSIManualDeduction {
        var request = SSICreateManualDeductionRequest(
            exclusionType: type,
            amountCents: amountCents,
            description: description,
            occurredOn: occurredOn,
            notes: notes
        )
        request.receiptAssetId = receipt.assetId
        request.receiptPending = receipt.pending
        request.vendor = receipt.vendor
        request.extractedAmountCents = receipt.extractedAmountCents
        request.extractedDate = receipt.extractedDate
        request.extractionConfidence = receipt.extractionConfidence
        request.counselorQuestion = receipt.counselorQuestion
        let row: SSIManualDeduction
        do {
            row = try await ssiService.createManualDeduction(request)
        } catch {
            Logger.error("BudgetDataManager: log manual deduction failed: \(error)")
            throw error
        }
        await refresh()
        return row
    }

    /// WP3 — attach an uploaded receipt to an existing entry.
    func attachReceipt(to deductionId: String, assetId: String) async throws {
        do {
            _ = try await ssiService.updateManualDeduction(
                deductionId, SSIUpdateManualDeductionRequest(receiptAssetId: assetId, receiptPending: false)
            )
        } catch {
            Logger.error("BudgetDataManager: attach receipt failed: \(error)")
            throw error
        }
        await refresh()
    }

    /// WP3 — rotor "Change type".
    func updateDeductionType(_ deductionId: String, to type: SSIExclusionType) async throws {
        do {
            _ = try await ssiService.updateManualDeduction(
                deductionId, SSIUpdateManualDeductionRequest(exclusionType: type)
            )
        } catch {
            Logger.error("BudgetDataManager: change deduction type failed: \(error)")
            throw error
        }
        await refresh()
    }

    /// Delete a manual deduction by row id, then refresh the
    /// overview so projected SSI updates.
    func deleteManualDeduction(_ deductionId: String) async throws {
        do {
            try await ssiService.deleteManualDeduction(deductionId)
        } catch {
            Logger.error("BudgetDataManager: delete manual deduction failed: \(error)")
            throw error
        }
        await refresh()
    }

    /// Phase 9 — fetch CSV export bytes and write to a temp file so
    /// the iOS share sheet (UIActivityViewController) can present
    /// it. Caller is responsible for cleaning up the temp file
    /// after the share sheet dismisses.
    func exportDeductionsCSVToTempFile(year: Int, month: Int?) async throws -> URL {
        let data: Data
        do {
            data = try await ssiService.exportDeductionsCSV(year: year, month: month)
        } catch {
            Logger.error("BudgetDataManager: export CSV failed: \(error)")
            throw error
        }
        let filename: String = {
            if let m = month {
                return String(format: "halofi-ssi-deductions-%04d-%02d.csv", year, m)
            }
            return String(format: "halofi-ssi-deductions-%04d.csv", year)
        }()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    // MARK: - WP6 — receipts on bank charges, monthly package, submission log

    /// Attach an uploaded receipt to a confirmed bank charge (exclusion).
    func attachReceipt(toExclusion exclusionId: String, assetId: String) async throws {
        do {
            try await ssiService.updateExclusion(exclusionId, SSIUpdateExclusionRequest(receiptAssetId: assetId))
        } catch {
            Logger.error("BudgetDataManager: attach receipt to exclusion failed: \(error)")
            throw error
        }
        markStale()
        await refresh()
    }

    /// Download the month's SSA-795 package to a temp file for share / print.
    func packetToTempFile(month: String, filename: String) async throws -> URL {
        let data = try await ssiService.downloadPacket(month: month)
        let safeName = filename.isEmpty ? "HaloFi_SSA795_\(month).pdf" : filename
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        try data.write(to: url, options: .atomic)
        return url
    }

    func emailPacket(month: String, to: String? = nil) async throws -> SSIEmailPacketResponse {
        do {
            return try await ssiService.emailPacket(month: month, to: to)
        } catch {
            Logger.error("BudgetDataManager: email packet failed: \(error)")
            throw error
        }
    }

    @discardableResult
    func markSubmitted(month: String, channel: String?, notes: String?) async throws -> SSISubmission {
        let row = try await ssiService.markSubmitted(month: month, channel: channel, notes: notes)
        markStale()
        await refresh()
        return row
    }

    @discardableResult
    func unmarkSubmitted(month: String) async throws -> SSISubmission {
        let row = try await ssiService.unmarkSubmitted(month: month)
        markStale()
        await refresh()
        return row
    }

    /// Phase 9b — server-side email export. The backend builds the
    /// same CSV the share-sheet path generates, attaches it to a
    /// transactional email, and sends to the user's account address
    /// via Mailgun. Returns the recipient + row count for an in-app
    /// confirmation line.
    func emailDeductionsCSV(
        year: Int,
        month: Int?,
        to: String? = nil
    ) async throws -> SSIEmailDeductionsResponse {
        do {
            return try await ssiService.emailDeductionsCSV(
                year: year,
                month: month,
                to: to
            )
        } catch {
            Logger.error("BudgetDataManager: email CSV failed: \(error)")
            throw error
        }
    }
}

// MARK: - Errors

/// WP3 — receipt-related fields carried alongside a manual deduction.
struct ManualDeductionReceiptFields: Equatable {
    var assetId: String? = nil
    var pending: Bool = false
    var vendor: String? = nil
    var extractedAmountCents: Int? = nil
    var extractedDate: String? = nil
    var extractionConfidence: Double? = nil
    var counselorQuestion: Bool = false
}

struct BudgetError: Error, LocalizedError {
    let underlying: Error

    var errorDescription: String? {
        (underlying as? LocalizedError)?.errorDescription
            ?? "We couldn't load your budget. Try again in a moment."
    }
}
