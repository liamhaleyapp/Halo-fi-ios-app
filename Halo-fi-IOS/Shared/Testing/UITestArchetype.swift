//
//  UITestArchetype.swift
//  Halo-fi-IOS
//
//  UI-test seam (WP4 §9). When the app is launched with
//  `--ui-test-archetype=<none|ssi_blind|ssi_unverified|ssdi|both>`,
//  MainTabView skips auth/onboarding, seeds the managers with fixtures for
//  that archetype, and every network refresh becomes a no-op. The UI tests
//  then assert each tab's first accessibility element per archetype.
//
//  Nothing here runs in a normal launch: `current` is nil unless the
//  argument is present, and the app never passes it to itself.
//

import Foundation

enum UITestArchetype: String, CaseIterable {
    case none, ssiBlind = "ssi_blind", ssiUnverified = "ssi_unverified", ssdi, both
    /// Answered the questionnaire: no SSI, no SSDI → no Benefits tab.
    case noneAnswered = "none_answered"
    /// SSI, resources in the 75–95 % watch band → alert banner + urgent header.
    case ssiWatch = "ssi_watch"

    static let argumentPrefix = "--ui-test-archetype="

    static let current: UITestArchetype? = {
        // Debug builds only: a TestFlight / App Store build must never be
        // able to seed fixture data on top of a real account.
        #if DEBUG
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix(argumentPrefix) {
            return UITestArchetype(rawValue: String(arg.dropFirst(argumentPrefix.count)))
        }
        #endif
        return nil
    }()

    /// `--ui-test-tab=<money|benefits|agent|settings>` — the tab to land on
    /// at launch (screenshot runs and UI tests that start off Money).
    static let tabArgumentPrefix = "--ui-test-tab="
    /// `--ui-test-notification=<kind>` — schedule a local notification with
    /// that userInfo kind two seconds after the tabs appear, so a UI test can
    /// background the app, tap the banner and prove the tap path is sound.
    static var notificationKind: String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--ui-test-notification=") }.map { String($0.dropFirst("--ui-test-notification=".count)) }
    }

    static let initialTab: MainTab? = {
        #if DEBUG
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix(tabArgumentPrefix) {
            switch String(arg.dropFirst(tabArgumentPrefix.count)) {
            case "money": return .money
            case "benefits": return .benefits
            case "agent": return .agent
            case "settings": return .settings
            default: return nil
            }
        }
        #endif
        return nil
    }()

    static var isActive: Bool { current != nil }

    var capabilities: UserCapabilities {
        switch self {
        case .none:
            return .none
        case .noneAnswered:
            return UserCapabilities(showsBenefitsLane: false, showsResourceCounter: false, showsSSDILane: false,
                                    expenseType: .none, bweLocked: false, coupleLimits: false, deemingReferral: false,
                                    showsWorkIncentives: false, benefitType: "none", blindStatus: "no",
                                    profileAnswered: true, getsSsaPayment: "no")
        case .ssiBlind, .ssiWatch:
            return UserCapabilities(showsBenefitsLane: true, showsResourceCounter: true, showsSSDILane: false,
                                    expenseType: .bwe, bweLocked: false, coupleLimits: false, deemingReferral: false,
                                    showsWorkIncentives: true, benefitType: "ssi", blindStatus: "yes",
                                    moneyProfileRemaining: self == .ssiWatch ? 4 : 0)
        case .ssiUnverified:
            return UserCapabilities(showsBenefitsLane: true, showsResourceCounter: true, showsSSDILane: false,
                                    expenseType: .irwe, bweLocked: true, coupleLimits: false, deemingReferral: false,
                                    showsWorkIncentives: true, benefitType: "ssi", blindStatus: "unverified")
        case .ssdi:
            return UserCapabilities(showsBenefitsLane: true, showsResourceCounter: false, showsSSDILane: true,
                                    expenseType: .irwe, bweLocked: false, coupleLimits: false, deemingReferral: false,
                                    showsWorkIncentives: true, benefitType: "ssdi", blindStatus: "no")
        case .both:
            return UserCapabilities(showsBenefitsLane: true, showsResourceCounter: true, showsSSDILane: true,
                                    expenseType: .bwe, bweLocked: false, coupleLimits: false, deemingReferral: false,
                                    showsWorkIncentives: true, benefitType: "both", blindStatus: "yes")
        }
    }

    var linkedItems: [ConnectedItem] {
        var result = [
            ConnectedItem(institutionId: "ins_1", institutionName: "Chase", availableProducts: ["transactions"],
                          itemId: "item-1", userId: "uitest", plaidItemId: "plaid-1", isActive: true,
                          lastSync: "2026-09-03T12:00:00Z", createdAt: nil, updatedAt: nil),
            ConnectedItem(institutionId: "ins_2", institutionName: "American Express", availableProducts: ["transactions"],
                          itemId: "item-2", userId: "uitest", plaidItemId: "plaid-2", isActive: true,
                          lastSync: "2026-09-03T12:00:00Z", createdAt: nil, updatedAt: nil),
        ]
        if ProcessInfo.processInfo.arguments.contains("--ui-test-investments") {
            result.append(ConnectedItem(institutionId: "ins_1", institutionName: "Chase", availableProducts: ["investments"],
                itemId: "item-3", userId: "uitest", plaidItemId: "plaid-3", isActive: true, lastSync: nil, createdAt: nil, updatedAt: nil))
        }
        return result
    }

    var accountsByItemId: [String: [BankAccount]] {
        var result = [
            "item-1": [
                BankAccount(name: "Chase Checking", mask: "1234", type: "depository", subtype: "checking",
                            currentBalance: 1214.00, availableBalance: 1200.00, currency: "USD",
                            idAccount: "acct-1", plaidItemId: "item-1", plaidAccountId: "p1", isActive: true, createdAt: nil, updatedAt: nil),
            ],
            "item-2": [
                BankAccount(name: "Amex Blue", mask: "1005", type: "credit", subtype: "credit card",
                            currentBalance: 1870.00, availableBalance: nil, currency: "USD",
                            idAccount: "acct-2", plaidItemId: "item-2", plaidAccountId: "p2", isActive: true, createdAt: nil, updatedAt: nil),
            ],
        ]
        if ProcessInfo.processInfo.arguments.contains("--ui-test-investments") {
            result["item-3"] = [BankAccount(name: "Investment account", mask: "7890", type: "investment", subtype: "brokerage",
                currentBalance: 5000, availableBalance: nil, currency: "USD", idAccount: "acct-3", plaidItemId: "item-3",
                plaidAccountId: "p3", isActive: true, createdAt: nil, updatedAt: nil)]
        }
        return result
    }

    /// Attention cards for this archetype (2026-09-05): SSI users get a
    /// package deadline and a deposit question; a non-benefit user only a
    /// bank to reconnect; the unanswered user nothing.
    /// The month ahead for this archetype (2026-09-05).
    var calendar: CalendarMonth? {
        guard self == .ssiWatch || self == .ssiBlind else { return nil }
        var json = """
        {"month": "2026-09", "month_label": "September 2026", "today": "2026-09-05",
         "days": [
           {"date": "2026-09-01", "is_today": false, "is_past": true, "items": [
             {"kind": "deadline", "label": "Social Security measures resources", "cents": 0, "confidence": "n/a", "source": "rule", "status": "past"},
             {"kind": "bill", "label": "XYZ Property", "cents": 85400, "confidence": "actual", "source": "matched", "status": "paid", "stream_id": "rent"}]},
           {"date": "2026-09-06", "is_today": false, "is_past": false, "items": [
             {"kind": "deadline", "label": "Hand in August work expenses", "cents": 0, "confidence": "n/a", "source": "reminder", "status": "due", "month": "2026-08"}]},
           {"date": "2026-09-18", "is_today": false, "is_past": false, "items": [
             {"kind": "income", "label": "Paycheck from Acme Payroll", "cents": 41200, "confidence": "medium", "source": "learned", "status": "expected"}]},
           {"date": "2026-09-27", "is_today": false, "is_past": false, "items": [
             {"kind": "subscription", "label": "Spotify", "cents": 1099, "confidence": "high", "source": "confirmed", "status": "expected", "stream_id": "spot"}]}
         ],
         "totals": {"expected_in_cents": 41200, "expected_out_cents": 1099},
         "next": {"kind": "deadline", "label": "Hand in August work expenses", "cents": 0, "confidence": "n/a", "source": "reminder", "status": "due", "date": "2026-09-06"},
         "spoken": "September: about $412 expected in, $11 going out. Next: Hand in August work expenses, September 6. Estimate."}
        """
        if ProcessInfo.processInfo.arguments.contains("--ui-test-calendar-disconnected") {
            json = json.replacingOccurrences(of: "\"stream_id\": \"spot\"", with:
                "\"stream_id\": \"spot\", \"bank_connection_status\": \"disconnected\", \"payment_verified\": false")
            json = json.replacingOccurrences(of: "Estimate.", with:
                "Some tracked payments are unverified because their bank connection is unavailable. Estimate.")
        }
        return try? JSONDecoder().decode(CalendarMonth.self, from: Data(json.utf8))
    }

    var attentionCards: [AttentionCard] {
        let json: String
        switch self {
        case .ssiWatch:
            json = """
            [{"id": "resources:act", "kind": "resources", "priority": 95, "title": "Act now on your SSI resources",
              "line": "1,800 dollars of 2,000 dollars. Social Security measures in 27 days.", "action_type": "open_resource_monitor",
              "payload": {}, "learn": false, "tone": "act"},
             {"id": "unlinked_cards", "kind": "unlinked_card", "priority": 60, "title": "Cards HaloFi can't see",
              "line": "About $2,484.00 a month goes to an American Express card that isn't linked. Link it and your budget can show where that money goes.",
              "action_type": "open_link_bank", "payload": {"labels": ["American Express"], "monthly_cents": 248400}, "learn": false, "tone": "watch"},
             {"id": "bill:rent", "kind": "bill_confirm", "priority": 35, "title": "Is XYZ Property a bill?",
              "line": "About $854.00 monthly. Next one expected September 27. Bills count in what is left by the 1st.",
              "action_type": "confirm_bill", "payload": {"stream_id": "rent", "merchant": "XYZ Property", "amount_cents": 85400,
              "frequency": "MONTHLY", "frequency_label": "monthly", "next_expected": "2026-09-27"}, "learn": true, "tone": "learn"}]
            """
        case .ssiBlind, .ssiUnverified, .both:
            json = """
            [{"id": "submit:2026-08", "kind": "submit_package", "priority": 90, "title": "Hand in August work expenses",
              "line": "Your August package is ready: 3 expenses. Field offices like to see it by September 6.",
              "action_type": "open_package", "payload": {"month": "2026-08"}, "learn": false, "tone": "watch"},
             {"id": "deposit:txn-dep-1", "kind": "deposit_label", "priority": 40, "title": "$412.00 from ACME PAYROLL",
              "line": "Arrived September 3. What is this? Work income, a benefit, a transfer, a refund, or a gift.",
              "action_type": "label_deposit", "payload": {"transaction_id": "txn-dep-1", "amount_cents": 41200, "source": "ACME PAYROLL", "occurred_on": "2026-09-03"},
              "learn": true, "tone": "learn"}]
            """
        case .ssdi:
            json = """
            [{"id": "deposit:txn-dep-1", "kind": "deposit_label", "priority": 40, "title": "$412.00 from ACME PAYROLL",
              "line": "Arrived September 3. What is this? Work income, a benefit, a transfer, a refund, or a gift.",
              "action_type": "label_deposit", "payload": {"transaction_id": "txn-dep-1", "amount_cents": 41200, "source": "ACME PAYROLL", "occurred_on": "2026-09-03"},
              "learn": true, "tone": "learn"}]
            """
        case .noneAnswered:
            json = """
            [{"id": "bank:item-1", "kind": "bank_reconnect", "priority": 85, "title": "Reconnect Chase",
              "line": "Its connection needs a fresh sign-in. Until then balances and charges stop updating.",
              "action_type": "open_accounts", "payload": {"item_id": "item-1"}, "learn": false, "tone": "watch"}]
            """
        case .none:
            json = "[]"
        }
        return (try? JSONDecoder().decode([AttentionCard].self, from: Data(json.utf8))) ?? []
    }

    /// A BudgetOverview for this archetype, decoded from JSON so it matches
    /// the wire shape exactly.
    var overview: BudgetOverview? {
        let watch = self == .ssiWatch
        let resources = watch
            ? """
              {"current_cents": 180000, "limit_cents": 200000, "remaining_cents": 20000, "pct_used": 90.0,
               "status": "warning", "formatted": {"current": "$1,800.00", "limit": "$2,000.00", "remaining": "$200.00"},
               "note": "", "excluded_cents": 0, "able_balance_cents": 0, "burial_fund_cents": 0, "v2_status": "warning",
               "band_status": "watch", "escalated": false, "pct_of_limit": 90.0, "days_until_measurement": 27,
               "measurement_date_iso": "2026-10-01", "spend_or_move_cents": 30000, "spend_or_move_formatted": "$300.00",
               "projection": {"measurement_date_iso": "2026-10-01", "countable_now_cents": 180000, "projected_cents": 194000,
                              "limit_cents": 200000, "band": "critical", "confidence": "medium", "inflow_cents": 99400, "outflow_cents": 85400,
                              "inflows": [{"kind": "ssa", "label": "Social Security payment", "expected_date_iso": "2026-09-30", "cents": 99400, "confidence": "high"}],
                              "outflows": [{"kind": "bill", "label": "Rent", "expected_date_iso": "2026-09-27", "cents": 85400, "confidence": "high"}],
                              "unconfirmed_bill_count": 1}}
              """
            : """
              {"current_cents": 121400, "limit_cents": 200000, "remaining_cents": 78600, "pct_used": 60.7,
               "status": "safe", "formatted": {"current": "$1,214.00", "limit": "$2,000.00", "remaining": "$786.00"},
               "note": "", "excluded_cents": 0, "able_balance_cents": 0, "burial_fund_cents": 0, "v2_status": "ok",
               "band_status": "ok", "escalated": false, "pct_of_limit": 60.7, "days_until_measurement": 27,
               "measurement_date_iso": "2026-10-01", "spend_or_move_cents": 0, "spend_or_move_formatted": "$0.00"}
              """
        let ssi = self == .none || self == .noneAnswered || self == .ssdi
            ? """
              {"has_ssi": false, "household_size": null, "resources": null, "income": null,
               "next_ssa_deposit": null, "recent_ssa_deposits": null, "overpayment_flag": null,
               "overpayment_reason": null, "month": "September 2026", "engine_version": null, "voice_summary": null}
              """
            : """
              {"has_ssi": true, "household_size": 1,
               "resources": \(resources),
               "income": {"countable_cents": 0, "threshold_cents": 283000, "status": "safe",
                          "formatted": {"countable": "$0.00", "threshold": "$2,830.00"}, "note": "",
                          "fbr_cents": 99400, "projected_payment_cents": 99400, "eligible_for_cash": true, "earn_room_gross_cents": 207300},
               "next_ssa_deposit": null, "recent_ssa_deposits": null, "overpayment_flag": false, "overpayment_reason": null,
               "month": "September 2026", "engine_version": "v2", "voice_summary": "SSI status update.",
               "disclaimer": "Estimate for education only — Social Security makes all actual decisions."}
              """
        let json = """
        {"month": "September 2026",
         "period": {"start_utc": "2026-09-01T04:00:00Z", "end_utc": "2026-10-01T04:00:00Z"},
         "pending": {"count": 1, "outflow_cents": 5000, "credit_outflow_cents": 5000, "cash_outflow_cents": 0, "incoming_cents": 0, "currency": "USD", "transactions": [{"id": "pending-fixture", "name": "Example groceries", "account_name": "Example card", "mask": "1234", "amount_cents": 5000, "date": "2026-09-07"}]},
         "spending": {"pending_cents": 5000, "posted_cents": 139600, "total_cents": 144600, "count": 42, "currency": "USD", "group_by": "category",
                      "groups": [{"key": "food_and_drink", "total_cents": 52000, "count": 12, "pct_of_total": 36.0, "formatted": "$520.00"}],
                      "formatted": {"total": "$1,446.00"}},
         "budget_status": {"has_budget": true, "month": "September 2026",
                           "total": {"pending_spent_cents": 5000, "posted_spent_cents": 139600, "limit_cents": 350000, "spent_cents": 144600, "remaining_cents": 205400, "pct_used": 41.3, "pace_pct": 10.0, "status": "on_pace",
                                     "formatted": {"spent": "$1,446.00", "limit": "$3,500.00", "remaining": "$2,054.00"}},
                           "categories": [{"category_id": "c1", "category": "home_improvement", "limit_cents": 20000, "spent_cents": 26000,
                                           "remaining_cents": -6000, "pct_used": 130.0, "status": "over", "formatted": {"spent": "$260.00", "limit": "$200.00"}}]},
         "monthly_income": {"total_cents": 350000, "total_formatted": "$3,500.00",
                            "sources": {"paycheck": {"amount_cents": 350000, "monthly_cents": 350000, "frequency": "monthly", "name": "ADP"},
                                        "ssi": {"enabled": false, "amount_cents": null}, "ssdi": {"enabled": false, "amount_cents": null}},
                            "editable": true},
         "ssi_status": \(ssi),
         "ssi_profile": {"is_blind": \(self == .ssiBlind || self == .ssiWatch || self == .both), "has_able_account": false, "able_balance_cents": null, "burial_fund_cents": null},
         "ssi_alerts": [], "alerts": [], "as_of_utc": "2026-09-03T12:00:00Z"}
        """
        return try? JSONDecoder().decode(BudgetOverview.self, from: Data(json.utf8))
    }
}

#if DEBUG
import SwiftUI
import StoreKit
import RevenueCat

/// Entirely local checkout fixture. Only reachable alongside the existing
/// debug-only UI-test archetype flag; never sends SDK billing requests.
final class CheckoutFixturePeriod: SKProductSubscriptionPeriod {
    let periodUnit: SKProduct.PeriodUnit
    init(unit: SKProduct.PeriodUnit = .month) { self.periodUnit = unit; super.init() }
    override var numberOfUnits: Int { 1 }
    override var unit: SKProduct.PeriodUnit { periodUnit }
}

final class CheckoutFixtureProduct: SKProduct {
    let fixtureTier: SubscriptionTier
    let fixtureCycle: SubscriptionBillingCycle
    let legacyID: Bool
    init(tier: SubscriptionTier = .pro, cycle: SubscriptionBillingCycle = .monthly, legacyID: Bool = true) {
        self.fixtureTier = tier; self.fixtureCycle = cycle; self.legacyID = legacyID
        super.init()
    }
    override var productIdentifier: String {
        legacyID ? "checkout.fixture.pro" : "com.halofi.\(fixtureTier.title.lowercased()).\(fixtureCycle.rawValue)"
    }
    override var localizedTitle: String { "HaloFi \(fixtureTier.title)" }
    override var localizedDescription: String { "A sample plan for checkout testing." }
    override var price: NSDecimalNumber { NSDecimalNumber(string: fixtureCycle == .monthly ? "9.99" : "99.99") }
    override var priceLocale: Locale { Locale(identifier: "en_US") }
    override var subscriptionPeriod: SKProductSubscriptionPeriod? {
        CheckoutFixturePeriod(unit: fixtureCycle == .monthly ? .month : .year)
    }
}

@MainActor
final class CheckoutFixtureClient: SubscriptionClient {
    var appUserID: String?
    let mode: String
    init(mode: String) { self.mode = mode }
    func logIn(_ userID: String) async throws { appUserID = userID }
    func logOut() async throws { appUserID = nil }
    func packages() async throws -> [Package] {
        if mode == "empty" { return [] }
        if mode == "catalog" {
            return SubscriptionBillingCycle.allCases.flatMap { cycle in
                SubscriptionTier.allCases.reversed().map { tier in
                    Package(identifier: "fixture-\(tier.title.lowercased())-\(cycle.rawValue)",
                        packageType: cycle == .monthly ? .monthly : .annual,
                        storeProduct: StoreProduct(sk1Product: CheckoutFixtureProduct(tier: tier, cycle: cycle, legacyID: false)),
                        presentedOfferingContext: .init(offeringIdentifier: "fixture"), webCheckoutUrl: nil)
                }
            }
        }
        return [Package(identifier: "fixture-pro", packageType: .monthly,
                        storeProduct: StoreProduct(sk1Product: CheckoutFixtureProduct()),
                        presentedOfferingContext: .init(offeringIdentifier: "fixture"), webCheckoutUrl: nil)]
    }
    func customerInfo() async throws -> CustomerInfo {
        let data = Data(#"{"request_date":"2026-09-07T00:00:00Z","subscriber":{"first_seen":"2026-09-01T00:00:00Z","original_app_user_id":"checkout-fixture","subscriptions":{},"non_subscriptions":{},"entitlements":{}}}"#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CustomerInfo.self, from: data)
    }
    func purchase(_ package: Package) async throws -> (CustomerInfo, Bool) {
        if mode == "pending" { throw ErrorCode.paymentPendingError }
        return (try await customerInfo(), true)
    }
    func restore() async throws -> CustomerInfo {
        if mode == "empty" { throw URLError(.notConnectedToInternet) }
        return try await customerInfo()
    }
    func introEligible(_ productID: String) async -> Bool { false }
}

struct CheckoutFixtureHost: View {
    @State private var service: SubscriptionService
    init(mode: String) {
        let session = SubscriptionSession(client: CheckoutFixtureClient(mode: mode), lifetime: SessionLifetime())
        session.selectUser("checkout-fixture")
        _service = State(initialValue: SubscriptionService(session: session, pendingChange: { _ in nil }))
    }
    var body: some View {
        SubscriptionCheckoutView(service: service, onComplete: {})
            .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--ui-test-checkout-large") ? .accessibility5 : .large)
    }
}
#endif


#if DEBUG
struct BankIntroFixtureHost: View {
    @State private var opened = false
    var body: some View {
        NavigationStack {
            if opened {
                Text("Secure connection opened").accessibilityIdentifier("fixtureBankOpened")
            } else {
                PlaidIntroView(alreadyLinked: ["American Express", "Chase"]) { opened = true }
                    .background(Color.haloBackground)
                    .navigationTitle("Bank connection")
            }
        }
        .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--ui-test-bank-large") ? .accessibility5 : .large)
        .preferredColorScheme(.dark)
    }
}
#endif

#if DEBUG
extension UITestArchetype {
    static func transactionSearchPage(query: String, offset: Int) -> TransactionsResponse {
        let data = Data("""
        [{"id_transaction":"search-1","account_id":"acct-1","name":"GOOGLE WORKSPACE","merchant_name":"Google Workspace","amount":8.40,"currency":"USD","transaction_date":"2026-09-01","pending":false,"is_active":true,"created_at":"2026-09-01","updated_at":"2026-09-01"},
         {"id_transaction":"search-2","account_id":"acct-1","name":"GOOGLE WORKSPACE EXTRA","merchant_name":"Google Workspace","amount":12,"currency":"USD","transaction_date":"2026-09-08","pending":true,"is_active":true,"created_at":"2026-09-08","updated_at":"2026-09-08"},
         {"id_transaction":"search-3","account_id":"acct-1","name":"UBER TRIP","merchant_name":"Uber","amount":25,"currency":"USD","transaction_date":"2026-09-09","pending":false,"is_active":true,"created_at":"2026-09-09","updated_at":"2026-09-09"}]
        """.utf8)
        let all = (try? JSONDecoder().decode([Transaction].self, from: data)) ?? []
        let matches = all.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.displayName.localizedCaseInsensitiveContains(query) }
            .sorted { $0.transactionDate > $1.transactionDate }
        return TransactionsResponse(added: 0, cursor: nil, hasMore: false, transactions: Array(matches.dropFirst(offset)))
    }
}
#endif
