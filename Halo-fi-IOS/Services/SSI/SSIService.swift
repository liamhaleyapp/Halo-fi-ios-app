//
//  SSIService.swift
//  Halo-fi-IOS
//
//  Networking for the SSI deduction-confirmation flow (Phase 3).
//  Backed by /ssi/exclusions and /ssi/exclusions/candidates on the
//  Python API. Thin wrapper around NetworkService so the Budget view
//  isn't coupled to URL construction.
//

import Foundation

protocol SSIServiceProtocol {
    /// Unconfirmed BWE/IRWE candidates the backend classifier spotted
    /// for the current month. Empty list when the user has no SSI flag
    /// or no transactions this month look like deduction candidates.
    func fetchCandidates(userTz: String?) async throws -> SSICandidatesResponse

    /// User's confirmed deductions for the current month plus running
    /// totals per type (drives the "you've claimed $X of BWE" line).
    func fetchExclusions(userTz: String?) async throws -> SSIExclusionsResponse

    /// Confirm a candidate as a BWE / IRWE / burial deduction. Server
    /// is idempotent on (transaction_id, exclusion_type) — calling this
    /// twice with the same args returns the same row.
    @discardableResult
    func confirm(_ request: SSICreateExclusionRequest) async throws -> SSIExclusion

    /// Undo a previously confirmed deduction by row ID.
    func deleteExclusion(_ exclusionId: String) async throws
}

// MARK: - Request / response models

struct SSICreateExclusionRequest: Encodable, Equatable {
    let transactionId: String
    let exclusionType: SSIExclusionType
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case exclusionType = "exclusion_type"
        case notes
    }
}

enum SSIExclusionType: String, Codable, CaseIterable, Equatable {
    case bwe
    case irwe
    case burial
}

struct SSIDeductionCandidate: Codable, Equatable, Identifiable {
    let transactionId: String
    let suggestedType: SSIExclusionType
    let confidence: String        // "high" | "medium" | "low"
    let amountCents: Int
    let transactionDate: String
    let description: String
    let matchedKeywords: [String]
    let reason: String

    var id: String { "\(transactionId)-\(suggestedType.rawValue)" }

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case suggestedType = "suggested_type"
        case confidence
        case amountCents = "amount_cents"
        case transactionDate = "transaction_date"
        case description
        case matchedKeywords = "matched_keywords"
        case reason
    }
}

struct SSICandidatesResponse: Codable, Equatable {
    let month: String
    let candidates: [SSIDeductionCandidate]
    let isBlind: Bool

    enum CodingKeys: String, CodingKey {
        case month, candidates
        case isBlind = "is_blind"
    }
}

struct SSIExclusion: Codable, Equatable, Identifiable {
    let id: String
    let transactionId: String
    let exclusionType: SSIExclusionType
    let source: String
    let confirmedAt: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case transactionId = "transaction_id"
        case exclusionType = "exclusion_type"
        case source
        case confirmedAt = "confirmed_at"
        case notes
    }
}

struct SSIExclusionsResponse: Codable, Equatable {
    let month: String
    let exclusions: [SSIExclusion]
    let totalsCents: [String: Int]

    enum CodingKeys: String, CodingKey {
        case month, exclusions
        case totalsCents = "totals_cents"
    }
}

// MARK: - Implementation

final class SSIService: SSIServiceProtocol {
    static let shared = SSIService()

    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol = NetworkService.shared) {
        self.networkService = networkService
    }

    func fetchCandidates(userTz: String? = nil) async throws -> SSICandidatesResponse {
        let endpoint = SSIService.appendingTz(
            APIEndpoints.SSI.candidates, userTz: userTz
        )
        return try await networkService.authenticatedRequest(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            responseType: SSICandidatesResponse.self
        )
    }

    func fetchExclusions(userTz: String? = nil) async throws -> SSIExclusionsResponse {
        let endpoint = SSIService.appendingTz(
            APIEndpoints.SSI.exclusions, userTz: userTz
        )
        return try await networkService.authenticatedRequest(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            responseType: SSIExclusionsResponse.self
        )
    }

    @discardableResult
    func confirm(_ request: SSICreateExclusionRequest) async throws -> SSIExclusion {
        let body = try JSONEncoder().encode(request)
        return try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.createExclusion,
            method: .POST,
            body: body,
            responseType: SSIExclusion.self
        )
    }

    func deleteExclusion(_ exclusionId: String) async throws {
        let _: EmptyResponse = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.deleteExclusion(exclusionId),
            method: .DELETE,
            body: nil,
            responseType: EmptyResponse.self
        )
    }

    private static func appendingTz(_ endpoint: String, userTz: String?) -> String {
        guard let tz = userTz, !tz.isEmpty,
              let encoded = tz.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return endpoint
        }
        return endpoint + "?user_tz=\(encoded)"
    }
}
