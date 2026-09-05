//
//  AttentionService.swift
//  Halo-fi-IOS
//
//  "Needs your attention" (Liam, 2026-09-05): the server composes one
//  list from resource alerts, package/receipt reminders, banks to
//  reconnect, and learning questions (what a deposit was, the paystub
//  gross, a likely work expense). The phone shows the top three.
//

import Foundation

struct AttentionCard: Codable, Equatable, Identifiable {
    struct Payload: Codable, Equatable {
        var transactionId: String?
        var amountCents: Int?
        var source: String?
        var occurredOn: String?
        var month: String?
        var itemId: String?
        var labelId: String?
        var netCents: Int?
        var lastGrossCents: Int?
        var employer: String?
        var suggestedType: String?
        var transactionDate: String?
        var description: String?
        var confidence: String?
        var reason: String?
        var matchedKeywords: [String]?
        var count: Int?
        var rawName: String?
        var accountId: String?
        var sameSourceCount: Int?
        var pending: Bool?
        var suggestionId: String?
        var totalLimitCents: Int?
        var categoryCount: Int?
        var windowDays: Int?
        var hasBudget: Bool?
        var category: String?
        var spentCents: Int?
        var limitCents: Int?
        var remaining: Int?
        var streamId: String?
        var merchant: String?
        var frequency: String?
        var frequencyLabel: String?
        var lastDate: String?
        var nextExpected: String?
        var kind: String?
        var amountVaries: Bool?

        enum CodingKeys: String, CodingKey {
            case source, month, employer, description, confidence, reason, count, pending, merchant, frequency, category, remaining, kind
            case amountVaries = "amount_varies"
            case suggestionId = "suggestion_id"
            case totalLimitCents = "total_limit_cents"
            case categoryCount = "category_count"
            case windowDays = "window_days"
            case hasBudget = "has_budget"
            case spentCents = "spent_cents"
            case limitCents = "limit_cents"
            case streamId = "stream_id"
            case frequencyLabel = "frequency_label"
            case lastDate = "last_date"
            case nextExpected = "next_expected"
            case rawName = "raw_name"
            case accountId = "account_id"
            case sameSourceCount = "same_source_count"
            case transactionId = "transaction_id"
            case amountCents = "amount_cents"
            case occurredOn = "occurred_on"
            case itemId = "item_id"
            case labelId = "label_id"
            case netCents = "net_cents"
            case lastGrossCents = "last_gross_cents"
            case suggestedType = "suggested_type"
            case transactionDate = "transaction_date"
            case matchedKeywords = "matched_keywords"
        }
    }

    let id: String
    let kind: String
    let priority: Int
    let title: String
    let line: String
    let actionType: String
    let payload: Payload
    let learn: Bool
    let tone: String

    enum CodingKeys: String, CodingKey {
        case id, kind, priority, title, line, payload, learn, tone
        case actionType = "action_type"
    }

    /// The candidate the existing confirm sheet needs, when this is one.
    var candidate: SSIDeductionCandidate? {
        guard actionType == "confirm_candidate", let txn = payload.transactionId,
              let type = SSIExclusionType(rawValue: payload.suggestedType ?? "irwe") else { return nil }
        return SSIDeductionCandidate(
            transactionId: txn, suggestedType: type, confidence: payload.confidence ?? "medium",
            amountCents: payload.amountCents ?? 0, transactionDate: payload.transactionDate ?? "",
            description: payload.description ?? "", matchedKeywords: payload.matchedKeywords ?? [], reason: payload.reason ?? ""
        )
    }
}

struct AttentionResponse: Codable, Equatable {
    let today: String
    let cards: [AttentionCard]
    /// Learning questions behind the stack, in order: the sheet walks them
    /// one after another without waiting on the server.
    let queue: [AttentionCard]
    let moreCount: Int

    enum CodingKeys: String, CodingKey {
        case today, cards, queue
        case moreCount = "more_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        today = try c.decode(String.self, forKey: .today)
        cards = try c.decode([AttentionCard].self, forKey: .cards)
        queue = try c.decodeIfPresent([AttentionCard].self, forKey: .queue) ?? []
        moreCount = try c.decodeIfPresent(Int.self, forKey: .moreCount) ?? 0
    }
}

protocol AttentionServiceProtocol {
    func fetch(userTz: String?) async throws -> AttentionResponse
    func dismiss(cardId: String, days: Int) async throws
}

final class AttentionService: AttentionServiceProtocol {
    static let shared = AttentionService()

    func fetch(userTz: String?) async throws -> AttentionResponse {
        var endpoint = APIEndpoints.Attention.me
        if let tz = userTz, let enc = tz.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            endpoint += "?user_tz=\(enc)"
        }
        return try await NetworkService.shared.authenticatedRequest(
            endpoint: endpoint, method: .GET, body: nil, responseType: AttentionResponse.self
        )
    }

    private struct DismissBody: Encodable { let days: Int }
    private struct DismissOut: Codable { let card_id: String; let until: String }

    func dismiss(cardId: String, days: Int) async throws {
        let _: DismissOut = try await NetworkService.shared.authenticatedRequest(
            endpoint: APIEndpoints.Attention.dismiss(cardId), method: .POST,
            body: try JSONEncoder().encode(DismissBody(days: days)), responseType: DismissOut.self
        )
    }
}
