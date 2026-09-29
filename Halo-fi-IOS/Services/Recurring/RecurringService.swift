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
    /// Who answered "is this a bill?" (2026-09-29): "user", or "halo" when
    /// HaloFi assumed an obvious subscription (Netflix) without asking.
    var confirmedBy: String? = nil
    var amountVaries: Bool? = nil
    var cancelledOn: String? = nil
    var lifecycleRevision: Int? = nil
    var forecastStatus: String? = nil
    var chargedAfterCancellation: Bool? = nil
    /// The amount to show everywhere (2026-09-28): the mode/median of
    /// regular charges, lump sums excluded. Older servers send only the average.
    var typicalCents: Int? = nil
    /// mode | median | single | provider
    var typicalBasis: String? = nil
    var extraPayments: [ExtraPayment]? = nil
    var amountChanged: AmountChange? = nil
    var logoUrl: String? = nil

    struct ExtraPayment: Codable, Equatable {
        let date: String
        let cents: Int
    }
    struct AmountChange: Codable, Equatable {
        let fromCents: Int
        let toCents: Int
        let since: String
        enum CodingKeys: String, CodingKey {
            case since
            case fromCents = "from_cents"
            case toCents = "to_cents"
        }
    }

    var displayCents: Int { typicalCents ?? averageCents }
    /// HaloFi answered for the user; the sheet says so and offers the change.
    var assumedByHalo: Bool { confirmedBy == "halo" }
    /// "Your bank shows: VT STATE HO-0128 DES:LL RENT. Last charge $854.00 on
    /// September 1." — the raw descriptor so a blind user can recognise a
    /// cryptic payee as rent. Nil when the bank sent no descriptor.
    var evidenceLine: String? {
        guard let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty else { return nil }
        var line = "Your bank shows: \(description). Last charge \(BudgetFormatter.cents(lastCents))"
        if let lastDate { line += " on \(TabSummaries.spokenDate(lastDate))" }
        return line + "."
    }
    /// "Was $50.00, now $55.00 since September 1." when the amount moved.
    var amountChangedLine: String? {
        amountChanged.map { "Was \(BudgetFormatter.cents($0.fromCents)), now \(BudgetFormatter.cents($0.toCents)) since \(TabSummaries.spokenDate($0.since))." }
    }
    /// "Extra payments not counted: September 3 $120.00, August 1 $80.00."
    var extraPaymentsLine: String? {
        guard let extra = extraPayments, !extra.isEmpty else { return nil }
        return "Extra payments not counted: " + extra.map { "\(TabSummaries.spokenDate($0.date)) \(BudgetFormatter.cents($0.cents))" }.joined(separator: ", ") + "."
    }
    var forecastLine: String {
        if chargedAfterCancellation == true { return "Charge recorded after cancellation. Review this payment." }
        if forecastStatus == "cancelled" { return "Cancelled. Kept for your records." }
        if forecastStatus == "interrupted" { return "Payment pattern stopped." + (lastDate.map { " Last charge \(TabSummaries.spokenDate($0))." } ?? "") }
        if forecastStatus == "unverified" { return "Bank data unavailable; next payment unverified." }
        return nextExpected.map { "Next expected \(TabSummaries.spokenDate($0))." } ?? "Next payment unverified."
    }

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
        case confirmedBy = "confirmed_by"
        case amountVaries = "amount_varies"
        case cancelledOn = "cancelled_on", lifecycleRevision = "lifecycle_revision"
        case forecastStatus = "forecast_status", chargedAfterCancellation = "charged_after_cancellation"
        case typicalCents = "typical_cents", typicalBasis = "typical_basis"
        case extraPayments = "extra_payments", amountChanged = "amount_changed"
        case logoUrl = "logo_url"
    }
}

struct RecurringResponse: Codable, Equatable {
    let today: String
    let streams: [RecurringStream]

    /// One row per subscription: two streams with the same merchant and
    /// account at about the same price (within 15%) are one row, and the one
    /// charged most recently stands in. A clearly different price is another
    /// product and stays (the server dedupes the same way; belt and braces).
    var dedupedStreams: [RecurringStream] {
        var kept: [RecurringStream] = []
        for s in streams {
            let twin = kept.firstIndex { k in
                k.merchant.lowercased() == s.merchant.lowercased() && (k.accountId ?? "") == (s.accountId ?? "")
                    && abs(k.displayCents - s.displayCents) <= Int(0.15 * Double(max(k.displayCents, s.displayCents, 1)))
            }
            if let twin {
                if (s.lastDate ?? "") > (kept[twin].lastDate ?? "") { kept[twin] = s }
            } else {
                kept.append(s)
            }
        }
        return kept
    }
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

    private struct CancellationBody: Encodable { let cancelled_on: String?; let expected_revision: Int }
    func setCancellation(stream: RecurringStream, date: String?) async throws -> RecurringStream {
        let out: ConfirmOut = try await NetworkService.shared.authenticatedRequest(
            endpoint: "/bank/recurring/\(stream.streamId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stream.streamId)/cancellation",
            method: .POST, body: try JSONEncoder().encode(CancellationBody(cancelled_on: date, expected_revision: stream.lifecycleRevision ?? 0)), responseType: ConfirmOut.self)
        return out.stream
    }

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
