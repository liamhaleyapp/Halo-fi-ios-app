//
//  BudgetService.swift
//  Halo-fi-IOS
//
//  Networking for the Budget view. Thin wrapper around NetworkService
//  so BudgetDataManager isn't coupled to URL construction.
//

import Foundation

protocol BudgetServiceProtocol {
    /// Aggregated budget view for the authenticated user.
    func getOverview(userTz: String?) async throws -> BudgetOverview

    /// Update the authenticated user's income profile fields.
    /// Returns nothing — view should refresh from /budget/overview after.
    func updateMonthlyIncome(_ update: MonthlyIncomeUpdate) async throws

    /// Update a single budget category's monthly limit (in dollars).
    /// View should refresh from /budget/overview after.
    func updateCategoryLimit(categoryId: String, limitAmount: Double) async throws

    // WP5
    func fetchSuggestion() async throws -> BudgetSuggestion?
    func applySuggestion() async throws
    func addCategory(code: String, limitAmount: Double) async throws
    func deleteCategory(categoryId: String) async throws
}

/// WP5 — GET /budget/suggestions payload.
struct BudgetSuggestion: Codable, Equatable {
    let id: String
    let generatedAt: String?
    let windowDays: Int
    let totalIncomeCents: Int
    let totalLimitCents: Int
    let proposal: [String: Int]
    let medians: [String: Int]
    let source: String
    let appliedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case generatedAt = "generated_at"
        case windowDays = "window_days"
        case totalIncomeCents = "total_income_cents"
        case totalLimitCents = "total_limit_cents"
        case proposal, medians, source
        case appliedAt = "applied_at"
    }

    struct Row: Identifiable, Equatable {
        let category: String
        let limitCents: Int
        let medianCents: Int?
        var id: String { category }
    }

    var rows: [Row] {
        proposal
            .sorted { $0.value > $1.value }
            .map { Row(category: $0.key, limitCents: $0.value, medianCents: medians[$0.key]) }
    }
}

private struct BudgetSuggestionEnvelope: Codable {
    let suggestion: BudgetSuggestion?
}

/// Mirrors the subset of the backend UserUpdateRequest that the Budget
/// editor modifies. All fields optional so we only send what changed.
struct MonthlyIncomeUpdate: Encodable, Equatable {
    var paycheckAmount: Double?
    var payFrequency: String?
    var paycheckName: String?
    var receivesSsi: Bool?
    var receivesSsdi: Bool?
    var ssiAmount: Double?
    var ssdiAmount: Double?
    // SSI rules-engine profile (Phase 4). Backend validates ranges
    // (cents >= 0; burial <= $1,500 cap).
    var isBlind: Bool?
    var hasAbleAccount: Bool?
    var ableBalanceCents: Int?
    var burialFundCents: Int?

    enum CodingKeys: String, CodingKey {
        case paycheckAmount = "paycheck_amount"
        case payFrequency = "pay_frequency"
        case paycheckName = "paycheck_name"
        case receivesSsi = "receives_ssi"
        case receivesSsdi = "receives_ssdi"
        case ssiAmount = "ssi_amount"
        case ssdiAmount = "ssdi_amount"
        case isBlind = "is_blind"
        case hasAbleAccount = "has_able_account"
        case ableBalanceCents = "able_balance_cents"
        case burialFundCents = "burial_fund_cents"
    }
}

final class BudgetService: BudgetServiceProtocol {
    static let shared = BudgetService()

    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol = NetworkService.shared) {
        self.networkService = networkService
    }

    func getOverview(userTz: String? = nil) async throws -> BudgetOverview {
        var endpoint = APIEndpoints.Budget.overview
        if let tz = userTz, !tz.isEmpty,
           let encoded = tz.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            endpoint += "?user_tz=\(encoded)"
        }
        return try await networkService.authenticatedRequest(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            responseType: BudgetOverview.self
        )
    }

    func updateMonthlyIncome(_ update: MonthlyIncomeUpdate) async throws {
        let body = try JSONEncoder().encode(update)
        // PATCH /users/me returns the full updated user; we don't consume
        // that shape here — the caller refreshes the overview after.
        let _: EmptyResponse = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.User.me,
            method: .PATCH,
            body: body,
            responseType: EmptyResponse.self
        )
    }

    func fetchSuggestion() async throws -> BudgetSuggestion? {
        let env: BudgetSuggestionEnvelope = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.Budget.suggestions, method: .GET, body: nil,
            responseType: BudgetSuggestionEnvelope.self
        )
        return env.suggestion
    }

    func applySuggestion() async throws {
        let _: EmptyResponse = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.Budget.applySuggestions, method: .POST, body: nil,
            responseType: EmptyResponse.self
        )
    }

    func addCategory(code: String, limitAmount: Double) async throws {
        struct Body: Encodable { let category: String; let limit_amount: Double }
        let body = try JSONEncoder().encode(Body(category: code, limit_amount: limitAmount))
        let _: EmptyResponse = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.Budget.categories, method: .POST, body: body,
            responseType: EmptyResponse.self
        )
    }

    func deleteCategory(categoryId: String) async throws {
        let _: EmptyResponse = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.Budget.category(categoryId), method: .DELETE, body: nil,
            responseType: EmptyResponse.self
        )
    }

    func updateCategoryLimit(categoryId: String, limitAmount: Double) async throws {
        struct LimitUpdate: Encodable {
            let limit_amount: Double
        }
        let body = try JSONEncoder().encode(LimitUpdate(limit_amount: limitAmount))
        let _: EmptyResponse = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.Budget.category(categoryId),
            method: .PATCH,
            body: body,
            responseType: EmptyResponse.self
        )
    }
}
