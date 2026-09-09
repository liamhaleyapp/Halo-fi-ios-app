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
        let mode = DepositLabelSheet.mode(for: r.cards[1])
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

private final class ReminderTestService: AttentionServiceProtocol {
    var fail = false
    var saved: [(String, Int)] = []
    func fetch(userTz: String?) async throws -> AttentionResponse { throw URLError(.notConnectedToInternet) }
    func dismiss(cardId: String, days: Int) async throws {
        if fail { throw URLError(.notConnectedToInternet) }
        saved.append((cardId, days))
    }
}

@Suite @MainActor struct AttentionLifecycleTests {
    private func card(_ kind: String, item: String = "") throws -> AttentionCard {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "\(kind):\(item)", "kind": kind, "priority": 50, "title": kind, "line": "Test",
            "action_type": "open_accounts", "payload": ["item_id": item], "learn": false, "tone": "watch"
        ])
        return try JSONDecoder().decode(AttentionCard.self, from: data)
    }

    @Test func verifiedReconnectRemovesOnlyTheRepairedItemImmediately() throws {
        let manager = BudgetDataManager(attentionService: ReminderTestService())
        defer { manager.clearAllData() }
        manager.attentionCards = [try card("bank_reconnect", item: "chase"), try card("bank_reconnect", item: "td")]
        manager.attentionQueue = [try card("money_profile_incomplete")]
        NotificationCenter.default.post(name: .attentionSourceChanged, object: nil,
                                        userInfo: ["reconnected_item_id": "chase"])
        #expect(manager.attentionCards.map { $0.payload.itemId } == ["td"])
        #expect(manager.attentionQueue.count == 1)
    }

    @Test func verifiedProfileCompletionClearsBothListsWithoutPullToRefresh() throws {
        let manager = BudgetDataManager(attentionService: ReminderTestService())
        defer { manager.clearAllData() }
        manager.attentionCards = [try card("money_profile_incomplete"), try card("bank_reconnect", item: "chase")]
        manager.attentionQueue = [try card("profile_incomplete"), try card("unlinked_card")]
        NotificationCenter.default.post(name: .attentionSourceChanged, object: nil,
            userInfo: ["resolved_kinds": ["money_profile_incomplete", "profile_incomplete"]])
        #expect(manager.attentionCards.map(\.kind) == ["bank_reconnect"])
        #expect(manager.attentionQueue.map(\.kind) == ["unlinked_card"])
        #expect(manager.attentionMoreCount == 1)
    }

    @Test func failedReminderSaveKeepsCardAndSuccessfulSaveHonorsDelay() async throws {
        let service = ReminderTestService()
        let manager = BudgetDataManager(attentionService: service)
        defer { manager.clearAllData() }
        let reminder = try card("unlinked_card")
        manager.attentionCards = [reminder]
        service.fail = true
        let failed = await manager.dismissCard(reminder, days: 30)
        #expect(!failed)
        #expect(manager.attentionCards == [reminder])
        service.fail = false
        let saved = await manager.dismissCard(reminder, days: 90)
        #expect(saved)
        #expect(manager.attentionCards.isEmpty)
        #expect(service.saved.count == 1)
        #expect(service.saved[0].0 == reminder.id && service.saved[0].1 == 90)
    }
}


@Suite struct CalendarVerificationTests {
    private func decode(_ extra: String = "", status: String = "expected") throws -> CalendarItem {
        let json = """
        {"kind":"subscription","label":"Spotify","cents":1099,"confidence":"about",
         "source":"confirmed","status":"\(status)"\(extra)}
        """
        return try JSONDecoder().decode(CalendarItem.self, from: Data(json.utf8))
    }

    @Test func olderServerPayloadStillDecodes() throws {
        let item = try decode()
        #expect(item.paymentVerified == nil)
        #expect(item.statusDescription == "expected")
    }

    @Test func disconnectedPaymentIsExplicitInSharedVisualAndVoiceOverText() throws {
        let item = try decode(", \"bank_connection_status\":\"disconnected\", \"payment_verified\":false")
        #expect(item.statusDescription == "Expected. Bank disconnected; payment unverified.")
        let past = try decode(", \"bank_connection_status\":\"disconnected\", \"payment_verified\":false", status: "unverified")
        #expect(past.statusDescription == "Bank disconnected; payment unverified.")
        #expect(!past.statusDescription.contains("paid"))
    }

    @Test func postedPaymentRemainsPaidAndReconnectClearsWarning() throws {
        let posted = try decode(status: "paid")
        #expect(posted.statusDescription == "paid")
        let reconnected = try decode(", \"bank_connection_status\":\"connected\"")
        #expect(reconnected.statusDescription == "expected")
    }
}

@Suite struct AttentionGroupingTests {
    private func card(_ kind: String, month: String? = nil) throws -> AttentionCard {
        var payload: [String: String] = [:]
        if let month { payload["month"] = month }
        return try JSONDecoder().decode(AttentionCard.self, from: JSONSerialization.data(withJSONObject: [
            "id": kind + (month ?? ""), "kind": kind, "priority": 30, "title": kind, "line": "Test",
            "action_type": "open_accounts", "payload": payload, "learn": true, "tone": "learn"
        ]))
    }
    @Test func filingGrossStaysUrgentAndQuestionsAreGrouped() throws {
        let cards = try [card("bank_reconnect"), card("bill_confirm"), card("deposit_label"),
                         card("submit_package", month: "2026-08"), card("wage_gross", month: "2026-08"),
                         card("wage_gross", month: "2026-09")]
        let sections = AttentionSections(cards: cards)
        #expect(sections.alerts.count == 3)
        #expect(sections.groups.map { $0.cards.count } == [1, 2])
        #expect(sections.alerts.contains { $0.kind == "wage_gross" && $0.payload.month == "2026-08" })
    }
    @Test func verifiedBalanceRejectsInconsistentBreakdown() {
        let summary = VerifiedBalanceSummary(cashCents: 100, owedCents: 0, accounts: [.init(kind: "cash", cents: 99)], currency: "USD")
        #expect(!summary.isValid)
    }
}


@Suite struct AccountIdentityResponseTests {
    @Test func oldResponsesRemainCompatible() throws {
        let response = try JSONDecoder().decode(MultiItemsResponse.self, from: Data(#"{"success":true,"items":[]}"#.utf8))
        #expect(response.identityReviews == nil)
    }
    @Test func partialSummaryRetainsReviewWhenCached() throws {
        let json = #"{"cash_cents":100,"owed_cents":0,"currency":"USD","accounts":[{"kind":"cash","cents":100}],"identity_reviews":[{"account_id":"new","name":"Checking","mask":"1234","institution":"Test","candidates":[]}]}"#
        let summary = try JSONDecoder().decode(VerifiedBalanceSummary.self, from: Data(json.utf8))
        let cached = try JSONDecoder().decode(VerifiedBalanceSummary.self, from: JSONEncoder().encode(summary))
        #expect(cached.isValid)
        #expect(cached.identityReviews?.count == 1)
    }
}

@Suite struct BankLinkProgressTests {
    private func item(_ id: String = "chase", sync: String? = "new-sync") -> ConnectedItem {
        ConnectedItem(institutionId: "ins_chase", institutionName: "Chase", availableProducts: nil,
                      itemId: id, userId: "test", plaidItemId: id, isActive: true,
                      lastSync: sync, createdAt: nil, updatedAt: nil)
    }
    @Test func existingAccountsDoNotFinishANewLink() {
        #expect(!BankLinkProgress.isReady(items: [], initialSyncs: [:], connected: 4, reviews: 0, expected: 2))
        #expect(!BankLinkProgress.isReady(items: [item(sync: "old")], initialSyncs: ["chase": "old"], connected: 4, reviews: 0, expected: 2))
        #expect(!BankLinkProgress.isReady(items: [item()], initialSyncs: [:], connected: 4, reviews: 0, expected: 2,
                                        selectedIds: ["new-card", "copy"], observedIds: ["old-card", "other-card"]))
    }
    @Test func reviewAccountsCountAsReceivedButNotAsExtraMoney() {
        #expect(BankLinkProgress.isReady(items: [item()], initialSyncs: [:], connected: 1, reviews: 1, expected: 2,
                                       selectedIds: ["new-card", "copy"], observedIds: ["new-card", "copy"]))
        #expect(!BankLinkProgress.isReady(items: [item()], initialSyncs: [:], connected: 1, reviews: 0, expected: 2))
        #expect(BankLinkProgress.reviewNotice(institution: "Chase", count: 1).contains("history"))
    }
    @Test func providerIdentitySurvivesEmbeddedResponseAndReviewDecoding() throws {
        let account = try JSONDecoder().decode(ServerEmbeddedAccount.self, from: Data(#"{"account_id":"internal","plaid_account_id":"provider","name":"Card","mask":"1364","type":"credit","subtype":"credit card","balance":12}"#.utf8))
        #expect(account.toBankAccount(plaidItemId: "item").plaidAccountId == "provider")
        let review = try JSONDecoder().decode(AccountIdentityReview.self, from: Data(#"{"account_id":"internal","plaid_account_id":"provider","item_id":"item","name":"Card","mask":"1364","institution":"Chase","candidates":[]}"#.utf8))
        #expect(review.itemId == "item" && review.plaidAccountId == "provider")
    }
}
