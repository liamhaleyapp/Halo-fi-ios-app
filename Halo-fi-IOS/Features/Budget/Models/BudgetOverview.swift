//
//  BudgetOverview.swift
//  Halo-fi-IOS
//
//  Response model for GET /budget/overview. Every monetary field is
//  integer cents from the backend — never display the raw cents; always
//  pass through a formatter.
//

import Foundation

// MARK: - Top-level overview

struct BudgetOverview: Codable, Equatable {
    let month: String            // "April 2026"
    let period: BudgetPeriod
    let spending: BudgetSpending
    let budgetStatus: BudgetStatus
    let monthlyIncome: MonthlyIncome
    let ssiStatus: SSIStatus
    let alerts: [BudgetAlert]
    let asOfUtc: String

    enum CodingKeys: String, CodingKey {
        case month, period, spending
        case budgetStatus = "budget_status"
        case monthlyIncome = "monthly_income"
        case ssiStatus = "ssi_status"
        case alerts
        case asOfUtc = "as_of_utc"
    }
}

struct BudgetPeriod: Codable, Equatable {
    let startUtc: String
    let endUtc: String
    enum CodingKeys: String, CodingKey {
        case startUtc = "start_utc"
        case endUtc = "end_utc"
    }
}

// MARK: - Spending

struct BudgetSpending: Codable, Equatable {
    let totalCents: Int
    let count: Int
    let currency: String
    let groupBy: String?
    let groups: [BudgetSpendingGroup]
    let formatted: [String: String]

    enum CodingKeys: String, CodingKey {
        case totalCents = "total_cents"
        case count, currency
        case groupBy = "group_by"
        case groups, formatted
    }
}

struct BudgetSpendingGroup: Codable, Equatable, Identifiable {
    var id: String { key }
    let key: String
    let totalCents: Int
    let count: Int
    let pctOfTotal: Double
    let formatted: String

    enum CodingKeys: String, CodingKey {
        case key
        case totalCents = "total_cents"
        case count
        case pctOfTotal = "pct_of_total"
        case formatted
    }
}

// MARK: - Budget status

struct BudgetStatus: Codable, Equatable {
    let hasBudget: Bool
    let month: String?
    let total: BudgetStatusTotal?
    let categories: [BudgetStatusCategory]

    enum CodingKeys: String, CodingKey {
        case hasBudget = "has_budget"
        case month, total, categories
    }
}

struct BudgetStatusTotal: Codable, Equatable {
    let limitCents: Int
    let spentCents: Int
    let remainingCents: Int
    let pctUsed: Double
    let pacePct: Double
    let status: String     // "over" | "behind" | "on_pace" | "ahead"
    let formatted: [String: String]

    enum CodingKeys: String, CodingKey {
        case limitCents = "limit_cents"
        case spentCents = "spent_cents"
        case remainingCents = "remaining_cents"
        case pctUsed = "pct_used"
        case pacePct = "pace_pct"
        case status, formatted
    }
}

struct BudgetStatusCategory: Codable, Equatable, Identifiable, Hashable {
    var id: String { categoryId ?? category }
    /// BudgetCategory.id_budget_cat — needed to PATCH limit edits.
    /// Optional for forward-compat with older backend builds that didn't
    /// surface it; UI gates the edit affordance when missing.
    let categoryId: String?
    let category: String
    let limitCents: Int
    let spentCents: Int
    let remainingCents: Int
    let pctUsed: Double
    let status: String
    let formatted: [String: String]

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case category
        case limitCents = "limit_cents"
        case spentCents = "spent_cents"
        case remainingCents = "remaining_cents"
        case pctUsed = "pct_used"
        case status, formatted
    }

    // Manual hash — the `formatted` dictionary on a struct blocks Swift's
    // Hashable synthesis. `category` is the unique key for navigation
    // destinations, so hashing on it is sufficient + correct.
    func hash(into hasher: inout Hasher) {
        hasher.combine(category)
        hasher.combine(limitCents)
        hasher.combine(spentCents)
    }
}

// MARK: - Monthly income

struct MonthlyIncome: Codable, Equatable {
    let totalCents: Int
    let totalFormatted: String
    let sources: MonthlyIncomeSources
    let editable: Bool

    enum CodingKeys: String, CodingKey {
        case totalCents = "total_cents"
        case totalFormatted = "total_formatted"
        case sources, editable
    }
}

struct MonthlyIncomeSources: Codable, Equatable {
    let paycheck: PaycheckSource
    let ssi: BenefitSource
    let ssdi: BenefitSource
}

struct PaycheckSource: Codable, Equatable {
    let amountCents: Int?
    let monthlyCents: Int?
    let frequency: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case amountCents = "amount_cents"
        case monthlyCents = "monthly_cents"
        case frequency, name
    }
}

struct BenefitSource: Codable, Equatable {
    let enabled: Bool
    let amountCents: Int?

    enum CodingKeys: String, CodingKey {
        case enabled
        case amountCents = "amount_cents"
    }
}

// MARK: - SSI status

struct SSIStatus: Codable, Equatable {
    let hasSsi: Bool
    let householdSize: Int?
    let resources: SSIResources?
    let income: SSIIncome?
    let nextSsaDeposit: SSANextDeposit?
    let recentSsaDeposits: [SSAPastDeposit]?
    let overpaymentFlag: Bool?
    let overpaymentReason: String?
    let month: String?
    /// Set to "v2" when the backend SSI rules engine is enabled; nil
    /// when the legacy SGA-threshold response is in use.
    let engineVersion: String?

    enum CodingKeys: String, CodingKey {
        case hasSsi = "has_ssi"
        case householdSize = "household_size"
        case resources, income
        case nextSsaDeposit = "next_ssa_deposit"
        case recentSsaDeposits = "recent_ssa_deposits"
        case overpaymentFlag = "overpayment_flag"
        case overpaymentReason = "overpayment_reason"
        case month
        case engineVersion = "engine_version"
    }
}

struct SSIResources: Codable, Equatable {
    let currentCents: Int
    let limitCents: Int
    let remainingCents: Int
    let pctUsed: Double
    let status: String     // "safe" | "warning" | "over"
    let formatted: [String: String]
    let note: String
    // Engine v2 additions — nil when the legacy SGA-threshold path is
    // serving this response.
    let excludedCents: Int?       // ABLE + burial-fund exclusions
    let ableBalanceCents: Int?
    let burialFundCents: Int?
    let v2Status: String?         // "over" | "critical" | "warning" | "ok"

    enum CodingKeys: String, CodingKey {
        case currentCents = "current_cents"
        case limitCents = "limit_cents"
        case remainingCents = "remaining_cents"
        case pctUsed = "pct_used"
        case status, formatted, note
        case excludedCents = "excluded_cents"
        case ableBalanceCents = "able_balance_cents"
        case burialFundCents = "burial_fund_cents"
        case v2Status = "v2_status"
    }
}

struct SSIIncome: Codable, Equatable {
    let countableCents: Int
    let thresholdCents: Int
    let status: String
    let formatted: [String: String]
    let note: String
    // Engine v2 additions — `projectedPaymentCents` is THE number to
    // headline on the income card (the user's actual check this
    // month). All v2 fields are nil when the legacy SGA-threshold
    // path is serving this response, so the existing UI keeps working.
    let fbrCents: Int?
    let projectedPaymentCents: Int?
    let eligibleForCash: Bool?
    let earnRoomGrossCents: Int?
    let countableEarnedCents: Int?
    let countableUnearnedCents: Int?
    let waterfall: SSIIncomeWaterfall?
    let v2Note: String?

    enum CodingKeys: String, CodingKey {
        case countableCents = "countable_cents"
        case thresholdCents = "threshold_cents"
        case status, formatted, note
        case fbrCents = "fbr_cents"
        case projectedPaymentCents = "projected_payment_cents"
        case eligibleForCash = "eligible_for_cash"
        case earnRoomGrossCents = "earn_room_gross_cents"
        case countableEarnedCents = "countable_earned_cents"
        case countableUnearnedCents = "countable_unearned_cents"
        case waterfall
        case v2Note = "v2_note"
    }
}

/// Engine v2 step-by-step intermediates — surfaced so the agent and
/// the UI can "show their work" for users who want the full
/// breakdown of how a check amount was derived.
struct SSIIncomeWaterfall: Codable, Equatable {
    let earnedCents: Int
    let unearnedCents: Int
    let gieToUnearnedCents: Int
    let remainingGieCents: Int
    let afterEieCents: Int
    let afterIrweCents: Int
    let after50Cents: Int

    enum CodingKeys: String, CodingKey {
        case earnedCents = "earned_cents"
        case unearnedCents = "unearned_cents"
        case gieToUnearnedCents = "gie_to_unearned_cents"
        case remainingGieCents = "remaining_gie_cents"
        case afterEieCents = "after_eie_cents"
        case afterIrweCents = "after_irwe_cents"
        case after50Cents = "after_50_cents"
    }
}

struct SSANextDeposit: Codable, Equatable {
    let expectedDateIso: String
    let expectedAmountCents: Int
    let confidence: String  // "high" | "medium" | "low"

    enum CodingKeys: String, CodingKey {
        case expectedDateIso = "expected_date_iso"
        case expectedAmountCents = "expected_amount_cents"
        case confidence
    }
}

struct SSAPastDeposit: Codable, Equatable, Identifiable {
    var id: String { "\(date)-\(amountCents)" }
    let date: String
    let amountCents: Int
    let description: String

    enum CodingKeys: String, CodingKey {
        case date
        case amountCents = "amount_cents"
        case description
    }
}

// MARK: - Alerts

struct BudgetAlert: Codable, Equatable, Identifiable {
    let id: String
    let alertType: String        // e.g. "budget_category", "balance_low"
    let category: String?
    let thresholdCents: Int?
    let thresholdFormatted: String?
    let comparison: String       // "above" | "below"
    let enabled: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case alertType = "alert_type"
        case category
        case thresholdCents = "threshold_cents"
        case thresholdFormatted = "threshold_formatted"
        case comparison, enabled
        case createdAt = "created_at"
    }
}
