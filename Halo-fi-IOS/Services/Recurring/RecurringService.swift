//
//  RecurringService.swift
//  Halo-fi-IOS
//
//  Bills (2026-09-05): Plaid's recurring outflow streams with the user's
//  yes / no. Confirmed bills feed the projection to the 1st.
//

import Foundation

struct RecurringStream: Codable, Equatable, Identifiable {
    let streamId: String
    let merchant: String
    let description: String?
    let frequency: String
    let frequencyLabel: String
    let averageCents: Int
    let lastCents: Int
    let lastDate: String?
    let nextExpected: String?
    let isActive: Bool
    let userConfirmed: Bool?
    let institutionName: String?
    let accountId: String?

    var id: String { streamId }

    enum CodingKeys: String, CodingKey {
        case merchant, description, frequency
        case streamId = "stream_id"
        case frequencyLabel = "frequency_label"
        case averageCents = "average_cents"
        case lastCents = "last_cents"
        case lastDate = "last_date"
        case nextExpected = "next_expected"
        case isActive = "is_active"
        case userConfirmed = "user_confirmed"
        case institutionName = "institution_name"
        case accountId = "account_id"
    }
}

struct RecurringResponse: Codable, Equatable {
    let today: String
    let streams: [RecurringStream]
    let confirmedCount: Int
    let monthlyBillsCents: Int

    enum CodingKeys: String, CodingKey {
        case today, streams
        case confirmedCount = "confirmed_count"
        case monthlyBillsCents = "monthly_bills_cents"
    }
}

final class RecurringService {
    static let shared = RecurringService()

    private struct ConfirmBody: Encodable { let is_bill: Bool; let label: String? }
    private struct ConfirmOut: Codable { let stream: RecurringStream }

    func bills() async throws -> RecurringResponse {
        try await NetworkService.shared.authenticatedRequest(
            endpoint: "/bank/recurring?type=outflow", method: .GET, body: nil, responseType: RecurringResponse.self
        )
    }

    func confirm(streamId: String, isBill: Bool, label: String? = nil) async throws -> RecurringStream {
        let out: ConfirmOut = try await NetworkService.shared.authenticatedRequest(
            endpoint: "/bank/recurring/\(streamId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? streamId)", method: .POST,
            body: try JSONEncoder().encode(ConfirmBody(is_bill: isBill, label: label)), responseType: ConfirmOut.self
        )
        return out.stream
    }
}
