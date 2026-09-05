//
//  NotificationPolicyTests.swift
//  Halo-fi-IOSTests
//
//  One calm notification a day, urgent things once, nothing at night.
//

import Foundation
import Testing
@testable import Halo_fi_IOS

@Suite struct NotificationPolicyTests {
    private func card(_ id: String, kind: String, tone: String = "learn", title: String = "Label a deposit", dueOn: String? = nil) -> AttentionCard {
        var payload = AttentionCard.Payload()
        payload.dueOn = dueOn
        payload.month = "2026-08"
        return AttentionCard(id: id, kind: kind, priority: 40, title: title, line: "", actionType: "label_deposit",
                             payload: payload, learn: kind == "deposit_label", tone: tone)
    }

    private func at(_ hour: Int, day: Int = 5) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = day; c.hour = hour; c.minute = 30
        return Calendar.current.date(from: c)!
    }

    @Test func digestGoesOutNextMorningAndOnlyOncePerDay() {
        let now = at(14)
        let cards = [card("d1", kind: "deposit_label"), card("b1", kind: "bill_confirm", title: "Is Spotify a subscription?")]
        let first = NotificationPolicy.plan(cards: cards, now: now, history: NotificationHistory())
        #expect(first?.kind == .digest)
        #expect(Calendar.current.component(.hour, from: first!.fireAt) == 9)
        #expect(first!.fireAt > now)
        #expect(first!.body.contains("2 things are waiting"))
        let h = NotificationPolicy.recorded(first!, into: NotificationHistory())
        // Same open items the next morning: nothing more for three days.
        #expect(NotificationPolicy.plan(cards: cards, now: at(10, day: 6), history: h) == nil)
        #expect(NotificationPolicy.plan(cards: cards, now: at(10, day: 7), history: h) == nil)
        #expect(NotificationPolicy.plan(cards: cards, now: at(10, day: 9), history: h)?.kind == .digest)
    }

    @Test func newItemAfterADayEarnsANewDigestButNotWithinTwentyHours() {
        let cards = [card("d1", kind: "deposit_label")]
        let first = NotificationPolicy.plan(cards: cards, now: at(14), history: NotificationHistory())!
        let h = NotificationPolicy.recorded(first, into: NotificationHistory())
        let more = cards + [card("d2", kind: "deposit_label")]
        #expect(NotificationPolicy.plan(cards: more, now: at(12, day: 6), history: h) == nil)      // < 20 h after the 9 a.m. digest
        #expect(NotificationPolicy.plan(cards: more, now: at(10, day: 7), history: h)?.kind == .digest)
    }

    @Test func urgentFiresOnceAndNotAtNight() {
        let urgent = card("res", kind: "resources", tone: "act", title: "Act now on your SSI resources")
        let evening = NotificationPolicy.plan(cards: [urgent], now: at(22), history: NotificationHistory())!
        #expect(evening.kind == .urgent && Calendar.current.component(.hour, from: evening.fireAt) == 9)
        let daytime = NotificationPolicy.plan(cards: [urgent], now: at(11), history: NotificationHistory())!
        #expect(daytime.fireAt.timeIntervalSince(at(11)) < 120)
        let h = NotificationPolicy.recorded(daytime, into: NotificationHistory())
        // The same urgent item is never repeated; a digest can still follow.
        #expect(NotificationPolicy.plan(cards: [urgent], now: at(11, day: 6), history: h)?.kind == .digest)
    }

    @Test func packageIsUrgentOnlyNearItsDueDate() {
        let far = card("pkg", kind: "submit_package", tone: "watch", title: "Hand in August work expenses", dueOn: "2026-09-20")
        let near = card("pkg", kind: "submit_package", tone: "watch", title: "Hand in August work expenses", dueOn: "2026-09-06")
        #expect(NotificationPolicy.isUrgent(far, now: at(10)) == false)
        #expect(NotificationPolicy.isUrgent(near, now: at(10)) == true)
    }

    @Test func nothingOpenMeansNothingScheduled() {
        #expect(NotificationPolicy.plan(cards: [], now: at(10), history: NotificationHistory()) == nil)
    }
}
