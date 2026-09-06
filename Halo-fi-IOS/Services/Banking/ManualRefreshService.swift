//
//  ManualRefreshService.swift
//  Halo-fi-IOS
//
//  The metered "Refresh from bank" (Liam, 2026-09-06). Plaid's on-demand
//  refresh bills per use, so a person chooses it with a visible count:
//  "Use manual refresh 2 of 5 for September?" The server owns the count
//  and the sentences; this just asks and runs.
//

import Foundation

struct ManualRefreshStatus: Codable, Equatable {
    let plan: String
    let limit: Int
    let used: Int
    let remaining: Int
    let month: String
    let monthLabel: String
    let confirmLine: String?
    let exhaustedLine: String

    enum CodingKeys: String, CodingKey {
        case plan, limit, used, remaining, month
        case monthLabel = "month_label"
        case confirmLine = "confirm_line"
        case exhaustedLine = "exhausted_line"
    }
}

enum ManualRefreshService {
    /// The plan hint the server clamps to free / basic / pro / max.
    static func planHint(_ entitlements: [String]) -> String {
        let ids = entitlements.map { $0.lowercased() }
        if ids.contains(where: { $0.contains("max") }) { return "max" }
        if ids.contains(where: { $0.contains("pro") }) { return "pro" }
        if ids.contains(where: { $0.contains("basic") }) { return "basic" }
        return "free"
    }

    static func status(plan: String) async throws -> ManualRefreshStatus {
        let tz = TimeZone.current.identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await NetworkService.shared.authenticatedRequest(
            endpoint: "\(APIEndpoints.User.manualRefresh)?plan=\(plan)&tz=\(tz)", method: .GET, body: nil,
            responseType: ManualRefreshStatus.self)
    }

    /// Runs the refresh. Throws `ManualRefreshError.exhausted` when the
    /// server says the month is used up (HTTP 429).
    static func run(plan: String) async throws -> ManualRefreshStatus {
        struct Body: Encodable { let source: String; let plan: String; let tz: String }
        do {
            return try await NetworkService.shared.authenticatedRequest(
                endpoint: APIEndpoints.User.manualRefresh, method: .POST,
                body: try JSONEncoder().encode(Body(source: "settings", plan: plan, tz: TimeZone.current.identifier)),
                responseType: ManualRefreshStatus.self)
        } catch let error as AuthError {
            if case .serverError(let code, _) = error, code == 429 { throw ManualRefreshError.exhausted }
            throw error
        }
    }
}

enum ManualRefreshError: Error { case exhausted }
