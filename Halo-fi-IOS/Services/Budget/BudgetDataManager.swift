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

    // MARK: - Dependencies

    private let service: BudgetServiceProtocol
    private var refreshTask: Task<Void, Never>?

    // MARK: - Init

    init(service: BudgetServiceProtocol = BudgetService.shared) {
        self.service = service
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
