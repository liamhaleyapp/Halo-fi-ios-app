//
//  BudgetAccessibilitySummary.swift
//  Halo-fi-IOS
//
//  Phase 11 Track A — "Hear the whole picture in 5 seconds."
//
//  Builds the VoiceOver announcement spoken when the Budget tab
//  loads or refreshes. Sighted users never see this; blind users
//  hear it via UIAccessibility.post(.screenChanged) and immediately
//  know whether anything urgent is happening.
//
//  Design rules (driven by the rules engine §10 + accessibility-
//  first product brief):
//    - Lead with the headline (projected SSI for SSI users, or
//      budget pace for non-SSI).
//    - Critical alerts come BEFORE secondary status — a user
//      should hear "you're over the resource limit" within the
//      first sentence.
//    - Whole dollars only. No decimals. VoiceOver speaks ".00"
//      as "point zero zero" which is noise.
//    - Cap at three sentences. Anyone wanting more detail can
//      swipe through the cards or ask Halo.
//

import Foundation

enum BudgetAccessibilitySummary {

    /// Build the announcement text. Returns nil when the data
    /// isn't ready yet (caller skips the announcement).
    static func make(
        overview: BudgetOverview?,
        candidatesCount: Int,
        manualDeductionsCount: Int,
        unmatchedManualCount: Int
    ) -> String? {
        guard let overview else { return nil }

        var sentences: [String] = []
        sentences.append("Budget for \(overview.month).")

        if overview.ssiStatus.hasSsi {
            // SSI users — lead with the engine's pre-baked §10
            // narration when available (Phase 6). It already
            // covers resources + projected check + 1619(b) callout.
            if let voice = overview.ssiStatus.voiceSummary,
               !voice.isEmpty {
                sentences.append(voice)
            } else {
                // Pre-v2 fallback: synthesize from raw fields.
                if let line = legacyResourceLine(overview.ssiStatus.resources) {
                    sentences.append(line)
                }
                if let line = legacyIncomeLine(overview.ssiStatus.income) {
                    sentences.append(line)
                }
            }

            sentences.append(
                deductionsLine(
                    candidatesCount: candidatesCount,
                    manualDeductionsCount: manualDeductionsCount,
                    unmatchedManualCount: unmatchedManualCount
                )
            )
        } else {
            // Non-SSI users — a one-line budget headline.
            sentences.append(budgetHeadline(overview))
        }

        return sentences
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - SSI fallback (when voice_summary is missing)

    private static func legacyResourceLine(_ res: SSIResources?) -> String? {
        guard let res else { return nil }
        let status = res.v2Status ?? res.status
        let current = wholeDollars(res.currentCents)
        let limit = wholeDollars(res.limitCents)
        if status == "over" {
            let overBy = wholeDollars(max(0, res.currentCents - res.limitCents))
            return "Heads up — your countable resources are \(current), which is \(overBy) over the \(limit) limit."
        }
        let room = wholeDollars(max(0, res.limitCents - res.currentCents))
        return "Countable resources \(current), \(room) under the \(limit) limit."
    }

    private static func legacyIncomeLine(_ income: SSIIncome?) -> String? {
        guard let income else { return nil }
        if let projected = income.projectedPaymentCents {
            if income.eligibleForCash == false {
                return "Your countable income is high enough that this month's SSI check would be zero."
            }
            return "Projected SSI payment about \(wholeDollars(projected))."
        }
        return nil
    }

    // MARK: - Counts of pending work

    private static func deductionsLine(
        candidatesCount: Int,
        manualDeductionsCount: Int,
        unmatchedManualCount: Int
    ) -> String {
        var parts: [String] = []
        if candidatesCount > 0 {
            let plural = candidatesCount == 1 ? "candidate" : "candidates"
            parts.append("\(candidatesCount) deduction \(plural) to review")
        }
        if manualDeductionsCount > 0 {
            let plural = manualDeductionsCount == 1 ? "deduction" : "deductions"
            parts.append("\(manualDeductionsCount) \(plural) logged")
            if unmatchedManualCount > 0 {
                parts.append("\(unmatchedManualCount) waiting for bank match")
            }
        }
        if parts.isEmpty { return "" }
        return parts.joined(separator: ", ") + "."
    }

    // MARK: - Non-SSI budget headline

    private static func budgetHeadline(_ overview: BudgetOverview) -> String {
        let spent = wholeDollars(overview.spending.totalCents)
        // BudgetStatus carries enums per category; for the
        // headline we just speak total spent. The detail lives
        // inside the cards.
        return "Spent \(spent) so far this month."
    }

    // MARK: - Number formatting (VoiceOver-friendly)

    /// Whole-dollar string with comma separators and a trailing
    /// "dollars" / "dollar" word. Strips the .00 that VoiceOver
    /// reads as "point zero zero". Negatives floor at $0.
    private static func wholeDollars(_ cents: Int) -> String {
        let safe = max(0, cents)
        let dollars = Int((Double(safe) / 100.0).rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        let number = formatter.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
        return dollars == 1 ? "1 dollar" : "\(number) dollars"
    }
}
