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
    /// "bill" or "subscription" (the user's word, else HaloFi's guess).
    var kind: String? = nil
    /// user | auto | learned
    var kindSource: String? = nil
    var amountVaries: Bool? = nil

    var id: String { streamId }
    var isSubscription: Bool { kind == "subscription" }
    var kindWord: String { isSubscription ? "subscription" : "bill" }

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
        case kind
        case kindSource = "kind_source"
        case amountVaries = "amount_varies"
    }
}

struct RecurringResponse: Codable, Equatable {
    let today: String
    let streams: [RecurringStream]
    let confirmedCount: Int
    /// Everything confirmed, bills and subscriptions together.
    let monthlyBillsCents: Int
    var billsCount: Int? = nil
    var subscriptionsCount: Int? = nil
    var monthlyBillsOnlyCents: Int? = nil
    var monthlySubscriptionsCents: Int? = nil
    /// Card and loan payments from the statement itself (Plaid Liabilities), 2026-09-06.
    var statementPayments: [StatementPayment]? = nil

    enum CodingKeys: String, CodingKey {
        case today, streams
        case confirmedCount = "confirmed_count"
        case monthlyBillsCents = "monthly_bills_cents"
        case billsCount = "bills_count"
        case subscriptionsCount = "subscriptions_count"
        case monthlyBillsOnlyCents = "monthly_bills_only_cents"
        case monthlySubscriptionsCents = "monthly_subscriptions_cents"
    }
}

final class RecurringService {
    static let shared = RecurringService()

    private struct ConfirmBody: Encodable { let is_bill: Bool; let label: String?; let kind: String? }
    private struct ConfirmOut: Codable { let stream: RecurringStream }

    func bills() async throws -> RecurringResponse {
        try await NetworkService.shared.authenticatedRequest(
            endpoint: "/bank/recurring?type=outflow", method: .GET, body: nil, responseType: RecurringResponse.self
        )
    }

    func confirm(streamId: String, isBill: Bool, label: String? = nil, kind: String? = nil) async throws -> RecurringStream {
        let out: ConfirmOut = try await NetworkService.shared.authenticatedRequest(
            endpoint: "/bank/recurring/\(streamId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? streamId)", method: .POST,
            body: try JSONEncoder().encode(ConfirmBody(is_bill: isBill, label: label, kind: kind)), responseType: ConfirmOut.self
        )
        return out.stream
    }
}


/// A card or loan payment with the exact due date and minimum from the
/// statement, not inferred from history.
struct StatementPayment: Codable, Equatable, Identifiable {
    let accountId: String
    let label: String
    let name: String?
    let institutionName: String?
    let type: String
    let dueDate: String?
    let minimumCents: Int
    let statementBalanceCents: Int?
    let isOverdue: Bool
    let daysUntilDue: Int?

    var id: String { accountId }

    var dueSpoken: String? {
        guard let dueDate, let d = ISO8601DateFormatter.dateOnly.date(from: dueDate) else { return nil }
        return d.formatted(.dateTime.month(.wide).day())
    }

    /// One sentence for the row and for VoiceOver.
    var line: String {
        let minimum = minimumCents > 0 ? "Minimum \(VoiceOverFormatter.dollars(minimumCents))" : "Payment"
        if isOverdue { return "\(minimum). Past due." }
        if let due = dueSpoken { return "\(minimum), due \(due)." }
        return minimum + "."
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id", label, name, type
        case institutionName = "institution_name"
        case dueDate = "due_date"
        case minimumCents = "minimum_cents"
        case statementBalanceCents = "statement_balance_cents"
        case isOverdue = "is_overdue"
        case daysUntilDue = "days_until_due"
    }
}
