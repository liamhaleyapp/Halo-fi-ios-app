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

    // MARK: - Dependencies

    private let service: BudgetServiceProtocol
    private let ssiService: SSIServiceProtocol
    private var refreshTask: Task<Void, Never>?
    /// Marked nonisolated so `deinit` (which is implicitly
    /// nonisolated under Swift's concurrency model) can read it
    /// without violating MainActor isolation. NSObjectProtocol is
    /// Sendable, so this doesn't need the `unsafe` qualifier.
    private nonisolated var mutationObserver: NSObjectProtocol?

    // MARK: - Tuning

    /// How long a successful overview fetch is considered "fresh
    /// enough" to skip on tab re-appearance. Set high enough that
    /// rapid Budget ↔ Income tab-bouncing doesn't burn a GET on
    /// every hop, low enough that a user who comes back after a
    /// minute still sees current data without manually pulling to
    /// refresh. Voice-driven mutations call `markStale()` to bypass
    /// the window, so this only governs view-induced refreshes.
    private static let freshnessWindow: TimeInterval = 30

    // MARK: - Init

    init(
        service: BudgetServiceProtocol = BudgetService.shared,
        ssiService: SSIServiceProtocol = SSIService.shared
    ) {
        self.service = service
        self.ssiService = ssiService

        // Listen for out-of-band mutations (voice commands processed
        // by the agent) and invalidate the cache so the next tab
        // visit refetches. addObserver's `queue: .main` runs the
        // closure on the main thread, but Swift concurrency doesn't
        // treat that as MainActor-isolated — hop explicitly via Task.
        mutationObserver = NotificationCenter.default.addObserver(
            forName: .budgetDataDidMutate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.markStale()
            }
        }
    }

    deinit {
        if let mutationObserver {
            NotificationCenter.default.removeObserver(mutationObserver)
        }
    }

    // MARK: - API

    /// True when the cache is stale enough that the next view
    /// appearance should refetch. Driven by `lastFetched` and
    /// invalidated explicitly by `markStale()`. Read from
    /// `BudgetView.task` so tab-hopping doesn't burn redundant
    /// GETs while still picking up voice-driven mutations.
    var shouldRefresh: Bool {
        guard let lastFetched else { return true }
        return Date().timeIntervalSince(lastFetched) >= Self.freshnessWindow
    }

    /// Force the next `shouldRefresh` read to return true. Called
    /// by the `.budgetDataDidMutate` observer when an agent reply
    /// suggests server state may have changed underneath us, and
    /// callable directly by anything else that needs to bypass the
    /// freshness window without immediately fetching.
    func markStale() {
        lastFetched = nil
    }

    /// Pull the latest overview. Coalesces concurrent calls so hitting
    /// refresh three times in a row doesn't fire three requests.
    func refresh(userTz: String? = TimeZone.current.identifier) async {
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
    func saveCategoryLimit(categoryId: String, limitAmount: Double) async throws {
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

        // SSI deduction candidates — separate endpoint so a candidates
        // failure doesn't tank the whole Budget view. Non-SSI users
        // get an empty list back from the server, no error.
        do {
            let response = try await ssiService.fetchCandidates(userTz: userTz)
            ssiCandidates = response.candidates
        } catch {
            Logger.error("BudgetDataManager: fetch SSI candidates failed: \(error)")
            ssiCandidates = []
        }

        // Manual deductions — Phase 8.
        do {
            let response = try await ssiService.fetchManualDeductions(userTz: userTz)
            ssiManualDeductions = response.deductions
            ssiManualTotalsCents = response.totalsCents
        } catch {
            Logger.error("BudgetDataManager: fetch manual deductions failed: \(error)")
            ssiManualDeductions = []
            ssiManualTotalsCents = [:]
        }
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

    /// Log a manual deduction (Phase 8 — voice or UI entry). After
    /// success, refreshes the whole overview so projected SSI math
    /// reflects the new deduction.
    func logManualDeduction(
        type: SSIExclusionType,
        amountCents: Int,
        description: String,
        occurredOn: String? = nil,
        notes: String? = nil
    ) async throws {
        let request = SSICreateManualDeductionRequest(
            exclusionType: type,
            amountCents: amountCents,
            description: description,
            occurredOn: occurredOn,
            notes: notes
        )
        do {
            _ = try await ssiService.createManualDeduction(request)
        } catch {
            Logger.error("BudgetDataManager: log manual deduction failed: \(error)")
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

struct BudgetError: Error, LocalizedError {
    let underlying: Error

    var errorDescription: String? {
        (underlying as? LocalizedError)?.errorDescription
            ?? "We couldn't load your budget. Try again in a moment."
    }
}
