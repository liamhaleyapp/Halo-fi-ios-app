//
//  NotificationPolicy.swift
//  Halo-fi-IOS
//
//  What HaloFi is allowed to say, and when (Liam, 2026-09-05): at most ONE
//  notification a day, general and calm ("HaloFi has a few things for you
//  when you have a minute"), never at night, and never the same nudge day
//  after day. The one exception is something pressing — resources over or
//  about to be measured, a package due within two days, a receipt
//  overdue, a bank that needs a fresh sign-in — which may add a second,
//  specific notification once, and only once per item.
//
//  Pure: takes the attention cards + reminders and the history of what was
//  already sent, returns the notification to schedule (or nil). The
//  scheduler owns UNUserNotificationCenter; this owns the judgement.
//

import Foundation

struct PlannedNotification: Equatable {
    enum Kind: String { case digest, urgent }
    let kind: Kind
    let title: String
    let body: String
    let fireAt: Date
    /// Card / reminder ids this notification covers (remembered so they are
    /// not repeated).
    let itemIds: [String]
    /// Routing for the tap: reminder kind + month when it is one reminder.
    let routeKind: String
    let routeMonth: String
}

struct NotificationHistory: Codable, Equatable {
    var lastDigestAt: Date? = nil
    /// Item ids covered by the last digest — the same set is not nudged
    /// again for `repeatDays`.
    var lastDigestItemIds: [String] = []
    var urgentSentAt: [String: Date] = [:]   // item id → when
    var lastUrgentAt: Date? = nil
}

enum NotificationPolicy {
    static let deliveryHour = 9        // 9 a.m. local
    static let quietFrom = 20          // nothing scheduled to fire after 8 p.m.
    static let repeatDays = 3          // the same "things for you" waits 3 days
    static let urgentKinds: Set<String> = ["resources", "submit_package", "receipts_needed", "bank_reconnect"]

    /// The next 9 a.m. that is at least `minLead` in the future.
    static func nextDeliverySlot(after now: Date, minLead: TimeInterval = 5 * 60, calendar: Calendar = .current) -> Date {
        var slot = calendar.date(bySettingHour: deliveryHour, minute: 0, second: 0, of: now) ?? now
        while slot < now.addingTimeInterval(minLead) {
            slot = calendar.date(byAdding: .day, value: 1, to: slot) ?? slot.addingTimeInterval(86_400)
        }
        return slot
    }

    /// Daytime = between 9 a.m. and 8 p.m. local.
    static func isDaytime(_ date: Date, calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: date)
        return h >= deliveryHour && h < quietFrom
    }

    static func isUrgent(_ card: AttentionCard, now: Date, calendar: Calendar = .current) -> Bool {
        guard urgentKinds.contains(card.kind) else { return false }
        if card.kind == "resources" { return card.tone == "act" }
        if card.kind == "submit_package" {
            // Pressing only within two days of the date field offices like.
            guard let due = card.payload.dueOn, let d = Self.day(due) else { return false }
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: d).day ?? 99 <= 2
        }
        return true
    }

    /// Decide what, if anything, to schedule. Returns at most one
    /// notification; call again after it fires (the scheduler re-plans on
    /// every refresh, so a second urgent item the same day is still caught).
    static func plan(cards: [AttentionCard], now: Date = Date(), history: NotificationHistory,
                     calendar: Calendar = .current) -> PlannedNotification? {
        // 1. Something pressing that was never announced: one specific note.
        let urgent = cards.filter { isUrgent($0, now: now, calendar: calendar) && history.urgentSentAt[$0.id] == nil }
        if let first = urgent.first {
            let sentToday = history.lastUrgentAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            if !sentToday {
                // Not "in a minute": the person is in the app right now (that is
                // how the card was fetched). Ten minutes lets them finish; if
                // they are still in the app, the foreground guard swallows it.
                let fireAt = isDaytime(now, calendar: calendar) ? now.addingTimeInterval(10 * 60) : nextDeliverySlot(after: now, calendar: calendar)
                let benefits = ["resources", "submit_package", "receipts_needed"].contains(first.kind)
                let body = first.title + "." + (benefits ? " Estimate. A free benefits counselor can help." : "")
                return PlannedNotification(kind: .urgent, title: "HaloFi needs you", body: body,
                                           fireAt: fireAt, itemIds: [first.id],
                                           routeKind: first.kind, routeMonth: first.payload.month ?? "")
            }
        }

        // 2. Otherwise one calm digest a day, and only when there is something
        //    the last digest did not already cover, or 3 days have passed.
        //    "Something new" is judged on the non-learning cards: one fresh
        //    deposit question a day must not re-open the digest every morning.
        let ordered = cards.sorted { $0.priority > $1.priority }
        guard !ordered.isEmpty else { return nil }
        let keyIds = ordered.filter { !$0.learn }.map(\.id).isEmpty ? ["learn-only"] : ordered.filter { !$0.learn }.map(\.id)
        if let last = history.lastDigestAt {
            let sinceLast = now.timeIntervalSince(last)
            if sinceLast < 20 * 3600 { return nil }
            let unchanged = Set(keyIds) == Set(history.lastDigestItemIds)
            if unchanged && sinceLast < Double(repeatDays) * 86_400 { return nil }
        }
        let count = ordered.count
        let first = ordered[0].title
        let firstLower = first.prefix(3).uppercased() == first.prefix(3) ? first : first.prefix(1).lowercased() + first.dropFirst()
        let body: String
        if count == 1 {
            body = "One thing is waiting when you have a minute: \(firstLower)."
        } else {
            body = "\(count) things are waiting when you have a minute, like \(firstLower)."
        }
        return PlannedNotification(kind: .digest, title: "HaloFi", body: body,
                                   fireAt: nextDeliverySlot(after: now, calendar: calendar), itemIds: keyIds,
                                   routeKind: "attention", routeMonth: "")
    }

    /// Record what was scheduled so the next plan does not repeat it. Keyed
    /// on WHEN it was planned: recording the future fire time made the next
    /// plan think nothing had been sent yet and cancel the pending request.
    static func recorded(_ n: PlannedNotification, into history: NotificationHistory, now: Date = Date()) -> NotificationHistory {
        var h = history
        let stamp = min(now, n.fireAt)
        switch n.kind {
        case .urgent:
            for id in n.itemIds { h.urgentSentAt[id] = stamp }
            h.lastUrgentAt = stamp
            // Keep the map bounded.
            if h.urgentSentAt.count > 100 {
                let keep = h.urgentSentAt.sorted { $0.value > $1.value }.prefix(60)
                h.urgentSentAt = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            }
        case .digest:
            h.lastDigestAt = stamp
            h.lastDigestItemIds = n.itemIds
        }
        return h
    }

    private static func day(_ iso: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(iso.prefix(10)))
    }
}
