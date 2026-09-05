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
                                    showsWorkIncentives: true, benefitType: "ssi", blindStatus: "yes")
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
        [
            ConnectedItem(institutionId: "ins_1", institutionName: "Chase", availableProducts: ["transactions"],
                          itemId: "item-1", userId: "uitest", plaidItemId: "plaid-1", isActive: true,
                          lastSync: "2026-09-03T12:00:00Z", createdAt: nil, updatedAt: nil),
            ConnectedItem(institutionId: "ins_2", institutionName: "American Express", availableProducts: ["transactions"],
                          itemId: "item-2", userId: "uitest", plaidItemId: "plaid-2", isActive: true,
                          lastSync: "2026-09-03T12:00:00Z", createdAt: nil, updatedAt: nil),
        ]
    }

    var accountsByItemId: [String: [BankAccount]] {
        [
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
               "measurement_date_iso": "2026-10-01", "spend_or_move_cents": 30000, "spend_or_move_formatted": "$300.00"}
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
         "spending": {"total_cents": 144600, "count": 42, "currency": "USD", "group_by": "category",
                      "groups": [{"key": "food_and_drink", "total_cents": 52000, "count": 12, "pct_of_total": 36.0, "formatted": "$520.00"}],
                      "formatted": {"total": "$1,446.00"}},
         "budget_status": {"has_budget": true, "month": "September 2026",
                           "total": {"limit_cents": 350000, "spent_cents": 144600, "remaining_cents": 205400, "pct_used": 41.3, "pace_pct": 10.0, "status": "on_pace",
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
