//
//  CalendarService.swift
//  Halo-fi-IOS
//
//  The month ahead (2026-09-05): what the user confirmed, day by day —
//  labeled income and learned paychecks, the next SSI payment, bills and
//  subscriptions they said yes to, the package due date, the day SSA
//  measures. Built server-side from the same data the rest of the app uses.
//

import Foundation

struct CalendarItem: Codable, Equatable, Identifiable {
    let kind: String          // income | bill | subscription | deadline
    let label: String
    let cents: Int
    let confidence: String    // high | medium | about | actual | n/a
    let source: String
    let status: String        // expected | arrived | paid | due | past
    var streamId: String? = nil
    var month: String? = nil
    var date: String? = nil   // present on `next`
    var id: String { "\(kind)-\(label)-\(status)-\(cents)-\(date ?? "")" }

    enum CodingKeys: String, CodingKey {
        case kind, label, cents, confidence, source, status, month, date
        case streamId = "stream_id"
    }
}

struct CalendarDay: Codable, Equatable, Identifiable {
    let date: String
    let isToday: Bool
    let isPast: Bool
    let items: [CalendarItem]
    var id: String { date }
    enum CodingKeys: String, CodingKey {
        case date, items
        case isToday = "is_today"
        case isPast = "is_past"
    }
}

struct CalendarMonth: Codable, Equatable {
    struct Totals: Codable, Equatable {
        let expectedInCents: Int
        let expectedOutCents: Int
        enum CodingKeys: String, CodingKey {
            case expectedInCents = "expected_in_cents"
            case expectedOutCents = "expected_out_cents"
        }
    }
    let month: String
    let monthLabel: String
    let today: String
    let days: [CalendarDay]
    let totals: Totals
    let next: CalendarItem?
    let spoken: String?
    enum CodingKeys: String, CodingKey {
        case month, today, days, totals, next, spoken
        case monthLabel = "month_label"
    }
}

final class CalendarService {
    static let shared = CalendarService()

    func month(_ month: String? = nil, userTz: String? = TimeZone.current.identifier) async throws -> CalendarMonth {
        var endpoint = "/me/calendar"
        var parts: [String] = []
        if let month { parts.append("month=\(month)") }
        if let tz = userTz, let enc = tz.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { parts.append("user_tz=\(enc)") }
        if !parts.isEmpty { endpoint += "?" + parts.joined(separator: "&") }
        return try await NetworkService.shared.authenticatedRequest(endpoint: endpoint, method: .GET, body: nil, responseType: CalendarMonth.self)
    }
}
