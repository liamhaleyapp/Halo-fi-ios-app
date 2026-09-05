//
//  TabSummariesTests.swift
//  Halo-fi-IOSTests
//
//  The Benefits header leads with the most urgent item; the Money header
//  is the balance plus, for SSI users, the resource counter; the Benefits
//  tab exists only for benefit users and the not-yet-answered.
//

import Foundation
import Testing
@testable import Halo_fi_IOS

private func resources(status: String, current: Int = 121_400, days: Int? = 27) -> SSIResources {
    let json = """
    {"current_cents": \(current), "limit_cents": 200000, "remaining_cents": \(200_000 - current), "pct_used": 60.0,
     "status": "safe", "formatted": {}, "note": "", "v2_status": "\(status)", "band_status": "\(status)",
     "escalated": false, "pct_of_limit": 60.0, "days_until_measurement": \(days.map(String.init) ?? "null"),
     "measurement_date_iso": "2026-10-01"}
    """
    return try! JSONDecoder().decode(SSIResources.self, from: Data(json.utf8))
}

private func ssiStatus(_ res: SSIResources?) -> SSIStatus {
    let resJSON = res.map { r in
        """
        {"current_cents": \(r.currentCents), "limit_cents": \(r.limitCents), "remaining_cents": 0, "pct_used": 0,
         "status": "safe", "formatted": {}, "note": "", "v2_status": "\(r.effectiveStatus)",
         "days_until_measurement": \(r.daysUntilMeasurement.map(String.init) ?? "null")}
        """
    } ?? "null"
    let json = """
    {"has_ssi": true, "household_size": 1, "resources": \(resJSON),
     "income": {"countable_cents": 0, "threshold_cents": 283000, "status": "safe", "formatted": {}, "note": "",
                "fbr_cents": 99400, "projected_payment_cents": 99400},
     "next_ssa_deposit": null, "recent_ssa_deposits": null, "overpayment_flag": false, "overpayment_reason": null,
     "month": "September 2026", "engine_version": "v2", "voice_summary": null}
    """
    return try! JSONDecoder().decode(SSIStatus.self, from: Data(json.utf8))
}

private func reminder(kind: String) -> SSIReminder {
    let json = """
    {"id": "r1", "kind": "\(kind)", "title": "Monthly package", "body": "August's package is ready to hand in.",
     "due_on": "2026-09-06", "deduction_id": null, "exclusion_id": null, "transaction_id": null,
     "amount_cents": null, "occurred_on": null, "month": "2026-08", "vendor": null}
    """
    return try! JSONDecoder().decode(SSIReminder.self, from: Data(json.utf8))
}

private let ssiCaps = UITestArchetype.ssiBlind.capabilities
private let ssdiCaps = UITestArchetype.ssdi.capabilities

private func benefits(_ status: String, reminders: [SSIReminder] = [], receipts: Int = 0, caps: UserCapabilities = ssiCaps) -> TabSummary {
    TabSummaries.benefits(capabilities: caps, ssi: ssiStatus(resources(status: status)),
                          expensesThisMonth: 0, expensesTotalCents: 0, expensesImpactCents: 0,
                          reminders: reminders, needsReceiptCount: receipts)
}

@Suite struct BenefitsHeaderUrgencyTests {
    @Test func overTheLimitBeatsEverything() {
        let s = benefits("over", reminders: [reminder(kind: "submit_package")], receipts: 3)
        #expect(s.verdict == "Over the SSI resource limit")
        #expect(s.tone == .act)
    }

    @Test func actNowBeatsPackage() {
        #expect(benefits("critical", reminders: [reminder(kind: "submit_package")]).verdict == "Act now on resources")
    }

    @Test func packageBeatsReceiptsAndWatch() {
        let s = benefits("warning", reminders: [reminder(kind: "submit_package")], receipts: 2)
        #expect(s.verdict == "Monthly package due")
        #expect(s.tone == .watch)
    }

    @Test func receiptsBeatWatch() {
        #expect(benefits("warning", receipts: 2).verdict == "2 receipts still needed")
        #expect(benefits("warning", receipts: 1).verdict == "1 receipt still needed")
    }

    @Test func watchBandThenPlainLane() {
        #expect(benefits("warning").verdict == "Resources getting close")
        let ok = benefits("ok")
        #expect(ok.verdict == "Your SSI is on track")
        #expect(ok.detail.contains("Projected check about 994 dollars"))
        #expect(ok.isEstimate)
    }

    @Test func otherReminderKindsDoNotOutrankResources() {
        #expect(benefits("warning", reminders: [reminder(kind: "attach_receipt")]).verdict == "Resources getting close")
    }

    @Test func ssdiLaneNeverMentionsResources() {
        #expect(benefits("over", caps: ssdiCaps).verdict == "Your SSDI")
        #expect(benefits("ok", reminders: [reminder(kind: "submit_package")], caps: ssdiCaps).verdict == "Monthly package due")
    }

    @Test func unansweredUserGetsTheStartCopy() {
        let s = TabSummaries.benefits(capabilities: .none, ssi: nil, expensesThisMonth: 0, expensesTotalCents: 0, expensesImpactCents: 0)
        #expect(s.verdict == "No benefits set up")
        #expect(s.detail.contains("questionnaire"))
    }
}

@Suite struct MoneyHeaderTests {
    private func snapshot(_ res: SSIResources?) -> MoneySnapshot {
        MoneySnapshot(cashCents: 121_400, owedCents: 187_000, accountCount: 2, connectionsNeedingAttention: 0,
                      resources: res, budgetTotal: nil, spentCents: 0, daysLeft: nil, firstOverCategory: nil)
    }

    @Test func nonBenefitUserIsBalanceOnly() {
        let s = TabSummaries.money(snapshot(resources(status: "ok")), capabilities: .none)
        #expect(s.verdict == "Balance")
        #expect(!s.detail.contains("SSI"))
        #expect(s.subline == nil)
        #expect(!s.isEstimate)
    }

    @Test func ssiUserGetsBalanceThenResourceCounter() {
        let s = TabSummaries.money(snapshot(resources(status: "ok")), capabilities: ssiCaps)
        #expect(s.verdict == "Balance")
        #expect(s.detail.hasPrefix("Cash 1,214 dollars across 2 accounts. Owed 1,870 dollars. Counts toward your SSI limit: 1,214 dollars of 2,000 dollars, on track."))
        #expect(s.subline == nil)   // the gauge draws the counted figure; nothing else to draw without a projection
        #expect(s.isEstimate)
        #expect(s.tone == .positive)
    }

    @Test func projectionSentenceFollowsTheCountsLine() {
        let json = """
        {"current_cents": 180000, "limit_cents": 200000, "remaining_cents": 20000, "pct_used": 90.0, "status": "warning",
         "formatted": {}, "note": "", "v2_status": "warning", "days_until_measurement": 27,
         "projection": {"measurement_date_iso": "2026-10-01", "countable_now_cents": 180000, "projected_cents": 194000,
                        "limit_cents": 200000, "band": "critical", "confidence": "medium", "inflow_cents": 99400, "outflow_cents": 85400,
                        "inflows": [], "outflows": [], "unconfirmed_bill_count": 1}}
        """
        let res = try! JSONDecoder().decode(SSIResources.self, from: Data(json.utf8))
        let s = TabSummaries.money(snapshot(res), capabilities: ssiCaps)
        #expect(s.detail.contains("By October 1, about 1,940 dollars of 2,000 dollars, act now. 1 possible bill not counted yet."))
        #expect(s.subline?.contains("By October 1") == true)
    }

    @Test func watchBandCarriesMeasurementDateAndTone() {
        let s = TabSummaries.money(snapshot(resources(status: "warning", current: 180_000)), capabilities: ssiCaps)
        #expect(s.detail.contains("getting close. Social Security measures in 27 days."))
        #expect(s.tone == .watch)
    }
}

@Suite struct ResourceAlertBannerTests {
    @Test func silentWhileOnTrack() {
        #expect(ResourceAlertBanner.copy(for: resources(status: "ok")) == nil)
    }

    @Test func wordsCarryTheState() {
        #expect(ResourceAlertBanner.copy(for: resources(status: "warning", current: 180_000))?.title == "Getting close to your SSI resource limit")
        #expect(ResourceAlertBanner.copy(for: resources(status: "critical", current: 195_000))?.title == "Act now on your SSI resources")
        let over = ResourceAlertBanner.copy(for: resources(status: "over", current: 214_000))
        #expect(over?.title == "Over the SSI resource limit")
        #expect(over?.line == "2,140 dollars of 2,000 dollars. Social Security measures in 27 days. Estimate.")
        #expect(over?.tone == .act)
    }
}

@Suite struct VisibleTabsTests {
    @Test func unansweredKeepsTheBenefitsTab() {
        #expect(MainTab.visible(for: .none) == [.money, .benefits, .agent, .settings])
    }

    @Test func answeredNoBenefitsHidesIt() {
        #expect(MainTab.visible(for: UITestArchetype.noneAnswered.capabilities) == [.money, .agent, .settings])
    }

    @Test func promiseAloneKeepsTheTab() {
        // Backend flags profileAnswered after the promise; no real answer yet.
        let caps = UserCapabilities(showsBenefitsLane: false, showsResourceCounter: false, showsSSDILane: false, expenseType: .none,
                                    bweLocked: false, coupleLimits: false, deemingReferral: false, showsWorkIncentives: false,
                                    benefitType: nil, blindStatus: nil, profileAnswered: true, getsSsaPayment: nil)
        #expect(caps.benefitsUnanswered)
        #expect(MainTab.visible(for: caps).contains(.benefits))
    }

    @Test func unsureKeepsTheTab() {
        let caps = UserCapabilities(showsBenefitsLane: false, showsResourceCounter: false, showsSSDILane: false, expenseType: .none,
                                    bweLocked: false, coupleLimits: false, deemingReferral: false, showsWorkIncentives: false,
                                    benefitType: "unsure", blindStatus: nil, profileAnswered: false, getsSsaPayment: "unsure")
        #expect(caps.benefitsUnanswered)
        #expect(MainTab.visible(for: caps).contains(.benefits))
    }

    @Test func answeredNoOnOlderBackendHidesIt() {
        // profileAnswered absent (older backend), but a real "no" is present.
        let caps = UserCapabilities(showsBenefitsLane: false, showsResourceCounter: false, showsSSDILane: false, expenseType: .none,
                                    bweLocked: false, coupleLimits: false, deemingReferral: false, showsWorkIncentives: false,
                                    benefitType: "none", blindStatus: nil, profileAnswered: false, getsSsaPayment: "no")
        #expect(!caps.benefitsUnanswered)
        #expect(!MainTab.visible(for: caps).contains(.benefits))
    }

    @Test func benefitUsersKeepIt() {
        #expect(MainTab.visible(for: ssiCaps).contains(.benefits))
        #expect(MainTab.visible(for: ssdiCaps).contains(.benefits))
    }
}
