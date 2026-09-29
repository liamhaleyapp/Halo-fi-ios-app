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
    var highlight: String? = nil
    let kind: String          // income | bill | subscription | deadline
    let label: String
    let cents: Int
    let confidence: String    // high | medium | about | actual | n/a
    let source: String
    let status: String        // expected | arrived | paid | due | past
    var bankConnectionStatus: String? = nil
    var paymentVerified: Bool? = nil
    var verificationNote: String? = nil
    var streamId: String? = nil
    var month: String? = nil
    var date: String? = nil   // present on `next`
    var logoUrl: String? = nil
    var merchant: String? = nil
    var id: String { "\(kind)-\(label)-\(status)-\(cents)-\(date ?? "")" }
    var canManageRecurringPayment: Bool {
        (kind == "bill" || kind == "subscription") && !(streamId ?? "").isEmpty
    }

    /// Shared wording for visible text and the single VoiceOver row.
    var statusDescription: String {
        if paymentVerified == false {
            let note = verificationNote ?? (bankConnectionStatus == "disconnected"
                ? "Bank disconnected; payment unverified."
                : "Bank connection unavailable; payment unverified.")
            return status == "expected" ? "Expected. " + note : note
        }
        switch status {
        case "arrived": return "arrived"
        case "paid": return "paid"
        case "due": return "due today"
        case "overdue": return "past due"
        case "past": return ""
        case "unverified": return "payment unverified"
        default: return "expected"
        }
    }

    enum CodingKeys: String, CodingKey {
        case bankConnectionStatus = "bank_connection_status"
        case paymentVerified = "payment_verified"
        case verificationNote = "verification_note"
        case kind, label, cents, confidence, source, status, highlight, month, date, merchant
        case streamId = "stream_id"
        case logoUrl = "logo_url"
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
    /// The 30-day window (ISO dates) when built with `upcoming=true`.
    var windowStart: String? = nil
    var windowEnd: String? = nil
    var estimate: Bool? = nil
    enum CodingKeys: String, CodingKey {
        case month, today, days, totals, next, spoken, estimate
        case monthLabel = "month_label"
        case windowStart = "window_start"
        case windowEnd = "window_end"
    }

    /// "Sep 28 – Oct 27" from the window, else the server's month label.
    var windowLabel: String {
        guard let s = windowStart, let e = windowEnd,
              let sd = CalendarDates.ymd.date(from: String(s.prefix(10))),
              let ed = CalendarDates.ymd.date(from: String(e.prefix(10))) else { return monthLabel }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "\(f.string(from: sd)) – \(f.string(from: ed))"
    }
}

/// The calendar's ISO dates are local days: parse them in the local zone
/// (ISO8601DateFormatter reads UTC midnight, which drew "Sep 4" for "2026-09-05").
enum CalendarDates {
    static let ymd: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}

final class CalendarService {
    static let shared = CalendarService()

    /// The 30 days starting `offsetDays` from today (0 = the next 30 days).
    func upcoming(offsetDays: Int = 0, userTz: String? = TimeZone.current.identifier) async throws -> CalendarMonth {
        var endpoint = "/me/calendar"
        var parts = ["upcoming=true", "offset_days=\(max(0, offsetDays))"]
        if let tz = userTz, let enc = tz.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { parts.append("user_tz=\(enc)") }
        endpoint += "?" + parts.joined(separator: "&")
        return try await NetworkService.shared.authenticatedRequest(endpoint: endpoint, method: .GET, body: nil, responseType: CalendarMonth.self)
    }
}
