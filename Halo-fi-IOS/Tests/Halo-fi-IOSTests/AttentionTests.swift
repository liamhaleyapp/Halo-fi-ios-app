//
//  AttentionTests.swift
//  Halo-fi-IOSTests
//
//  Wire decoding of attention cards and the mappings the Money tab uses.
//

import Foundation
import Testing
@testable import Halo_fi_IOS

@Suite struct AttentionCardTests {
    private let json = """
    {"today": "2026-09-05", "more_count": 1, "cards": [
      {"id": "candidate:t1", "kind": "work_expense_candidate", "priority": 30, "title": "Was Uber a work expense?",
       "line": "$23.40 on September 2. Looks like a BWE: rideshare on a work day.", "action_type": "confirm_candidate",
       "payload": {"transaction_id": "t1", "suggested_type": "bwe", "amount_cents": 2340, "transaction_date": "2026-09-02",
                   "description": "Uber", "confidence": "high", "reason": "rideshare on a work day", "matched_keywords": ["uber"]},
       "learn": true, "tone": "learn"},
      {"id": "gross:t2", "kind": "wage_gross", "priority": 45, "title": "Paycheck from ACME", "line": "…",
       "action_type": "enter_gross", "payload": {"transaction_id": "t2", "label_id": "L1", "net_cents": 41200, "last_gross_cents": 64000,
                   "employer": "ACME", "occurred_on": "2026-09-04"}, "learn": true, "tone": "learn"}
    ]}
    """

    @Test func decodesAndMapsCandidate() throws {
        let r = try JSONDecoder().decode(AttentionResponse.self, from: Data(json.utf8))
        #expect(r.moreCount == 1 && r.cards.count == 2)
        let c = try #require(r.cards[0].candidate)
        #expect(c.transactionId == "t1" && c.suggestedType == .bwe && c.amountCents == 2340 && c.matchedKeywords == ["uber"])
        #expect(r.cards[1].candidate == nil)
    }

    @Test func grossCardBecomesGrossMode() throws {
        let r = try JSONDecoder().decode(AttentionResponse.self, from: Data(json.utf8))
        let mode = MoneyHomeView.labelMode(for: r.cards[1])
        #expect(mode == .gross(labelId: "L1", employer: "ACME", netCents: 41200, lastGrossCents: 64000, occurredOn: "2026-09-04"))
    }

    @Test func grossParsing() {
        #expect(DepositLabelSheet.cents(from: "640") == 64000)
        #expect(DepositLabelSheet.cents(from: "$1,234.56") == 123456)
        #expect(DepositLabelSheet.cents(from: "") == nil)
        #expect(DepositLabelSheet.cents(from: "0") == nil)
    }

    @Test func sourceLineReadsCadenceAndLastGross() {
        let s = IncomeSource(sourceKey: "acme", kind: "work_income", employer: "ACME", lastGrossCents: 64000, lastNetCents: 41200,
                             lastPaidOn: "2026-09-04", cadenceDays: 14)
        #expect(IncomeView.sourceLine(s) == "Work income · every 2 weeks · last gross $640.00")
    }
}
