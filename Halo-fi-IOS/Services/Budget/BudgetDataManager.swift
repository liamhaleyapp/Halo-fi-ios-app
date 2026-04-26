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

    // MARK: - Init

    init(
        service: BudgetServiceProtocol = BudgetService.shared,
        ssiService: SSIServiceProtocol = SSIService.shared
    ) {
        self.service = service
        self.ssiService = ssiService
    }

    // MARK: - API

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
}

// MARK: - Errors

struct BudgetError: Error, LocalizedError {
    let underlying: Error

    var errorDescription: String? {
        (underlying as? LocalizedError)?.errorDescription
            ?? "We couldn't load your budget. Try again in a moment."
    }
}
