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

    enum CodingKeys: String, CodingKey {
        case paycheckAmount = "paycheck_amount"
        case payFrequency = "pay_frequency"
        case paycheckName = "paycheck_name"
        case receivesSsi = "receives_ssi"
        case receivesSsdi = "receives_ssdi"
        case ssiAmount = "ssi_amount"
        case ssdiAmount = "ssdi_amount"
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
}
