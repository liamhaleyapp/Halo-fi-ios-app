//
//  ReceiptOCRParserTests.swift
//  Halo-fi-IOSTests
//
//  WP3 — the on-device parser that turns Vision's recognized lines into
//  amount / date / merchant. Pure function; no camera, no network.
//

import Foundation
import Testing
@testable import Halo_fi_IOS

struct ReceiptOCRParserTests {
    private let now = ISO8601DateFormatter().date(from: "2026-09-04T12:00:00Z")!

    @Test func uberEmailReceipt() {
        let lines = [
            "Uber",
            "Thanks for riding, Sam",
            "September 3, 2026",
            "Trip fare $19.80",
            "Booking fee $2.60",
            "Tip $1.00",
            "Total $23.40",
            "Payments Visa ••••1005 $23.40",
        ]
        let parse = ReceiptOCRParser.parse(lines: lines, now: now)
        #expect(parse.amountCents == 2340)
        #expect(parse.merchant == "Uber")
        #expect(parse.confidence >= ReceiptParse.fallbackThreshold)
        #expect(parse.needsFallback == false)
        let cal = Calendar.current
        #expect(cal.component(.month, from: parse.date!) == 9)
        #expect(cal.component(.day, from: parse.date!) == 3)
    }

    @Test func totalBeatsSubtotalAndTax() {
        let lines = ["CVS Pharmacy", "09/02/2026", "Subtotal 12.99", "Tax 0.78", "TOTAL 13.77", "Change 6.23"]
        let parse = ReceiptOCRParser.parse(lines: lines, now: now)
        #expect(parse.amountCents == 1377)
        #expect(parse.merchant == "CVS Pharmacy")
    }

    @Test func noTotalKeywordFallsBackToLargestAmount() {
        let lines = ["Metro Transit", "Fare 2.75", "Fare 2.75", "5.50"]
        let parse = ReceiptOCRParser.parse(lines: lines, now: now)
        #expect(parse.amountCents == 550)
        #expect(parse.needsFallback == true)   // no total line, no date → low confidence
    }

    @Test func emptyAndGarbage() {
        #expect(ReceiptOCRParser.parse(lines: [], now: now) == .empty)
        let parse = ReceiptOCRParser.parse(lines: ["|||", "1234567890", "----"], now: now)
        #expect(parse.amountCents == nil)
        #expect(parse.needsFallback == true)
    }

    @Test func futureAndAncientDatesIgnored() {
        #expect(ReceiptOCRParser.parseDate(in: "Expires 12/31/2030", now: now) == nil)
        #expect(ReceiptOCRParser.parseDate(in: "Member since 01/01/2015", now: now) == nil)
        #expect(ReceiptOCRParser.parseDate(in: "3 Sep 2026", now: now) != nil)
        #expect(ReceiptOCRParser.parseDate(in: "2026-09-03", now: now) != nil)
    }

    @Test func merchantHeuristics() {
        #expect(ReceiptOCRParser.looksLikeMerchant("Trader Joe's") == true)
        #expect(ReceiptOCRParser.looksLikeMerchant("Thank you for shopping") == false)
        #expect(ReceiptOCRParser.looksLikeMerchant("Store #4421 Reg 3") == false)
        #expect(ReceiptOCRParser.looksLikeMerchant("ab") == false)
    }

    @Test func moneyRegexHandlesThousands() {
        #expect(ReceiptOCRParser.moneyValues(in: "Total $1,234.56") == [123456])
        #expect(ReceiptOCRParser.moneyValues(in: "no money here 12") == [])
    }
}
