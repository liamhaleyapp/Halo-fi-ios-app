//
//  TabSummaries.swift
//  Halo-fi-IOS
//
//  Pure builders for the words each tab's summary header speaks, and the
//  Magic Tap read-out ("Money header, resource status, next due task").
//  Kept UI-free so the UI tests and the headers agree by construction.
//
//  Rules: verdict in words before numbers; whole dollars via
//  VoiceOverFormatter; SSI and SSDI never blended; every computed
//  benefits number is an estimate.
//

import Foundation

struct TabSummary: Equatable {
    let verdict: String
    let detail: String
    let isEstimate: Bool
    let tone: ScreenReaderSummaryHeader.Tone

    var spoken: String {
        var parts = ["\(verdict).", detail]
        if isEstimate { parts.append(ScreenReaderSummaryHeader.disclaimer) }
        return parts.joined(separator: " ")
    }
}

/// What the Money header needs to know, decoupled from the managers.
struct MoneySnapshot: Equatable {
    var cashCents: Int
    var owedCents: Int
    var accountCount: Int
    var connectionsNeedingAttention: Int
    var resources: SSIResources?
    var budgetTotal: BudgetStatusTotal?
    var spentCents: Int
    var daysLeft: Int?
    var firstOverCategory: String?
}

enum TabSummaries {
    // MARK: - Money

    static func money(_ s: MoneySnapshot, capabilities: UserCapabilities) -> TabSummary {
        var detail = ""
        var verdict = ""
        var tone: ScreenReaderSummaryHeader.Tone = .neutral
        var isEstimate = false

        if capabilities.showsResourceCounter, let res = s.resources {
            let (word, t) = resourceVerdict(res)
            verdict = word
            tone = t
            isEstimate = true
            detail = "Counted resources: \(VoiceOverFormatter.dollars(res.currentCents)) of \(VoiceOverFormatter.dollars(res.limitCents))."
            if let days = res.daysUntilMeasurement, res.effectiveStatus != "ok" {
                detail += " Social Security measures in \(days == 1 ? "1 day" : "\(days) days")."
            }
        } else {
            verdict = s.accountCount == 0 ? "No accounts linked" : "Balance"
            let accounts = VoiceOverFormatter.count(s.accountCount, singular: "account", plural: "accounts")
            detail = "Cash \(VoiceOverFormatter.dollars(s.cashCents)) across \(accounts). Owed \(VoiceOverFormatter.dollars(s.owedCents))."
            tone = s.owedCents > s.cashCents ? .watch : .positive
        }
        if s.connectionsNeedingAttention > 0 {
            detail += " \(VoiceOverFormatter.count(s.connectionsNeedingAttention, singular: "connection", plural: "connections")) need\(s.connectionsNeedingAttention == 1 ? "s" : "") attention."
        }
        return TabSummary(verdict: verdict, detail: detail, isEstimate: isEstimate, tone: tone)
    }

    /// The budget summary row under the Money header.
    static func budgetRow(_ s: MoneySnapshot) -> String {
        guard let total = s.budgetTotal else {
            return "No budget yet. Spent \(VoiceOverFormatter.dollars(s.spentCents)) this month."
        }
        var line = "Spent \(VoiceOverFormatter.dollars(total.spentCents)) of \(VoiceOverFormatter.dollars(total.limitCents)) this month"
        if let days = s.daysLeft { line += ", \(days == 1 ? "1 day" : "\(days) days") left" }
        line += "."
        if let over = s.firstOverCategory { line += " Over in \(over)." }
        return line
    }

    // MARK: - Benefits

    static func benefits(
        capabilities: UserCapabilities,
        ssi: SSIStatus?,
        expensesThisMonth: Int,
        expensesTotalCents: Int,
        expensesImpactCents: Int
    ) -> TabSummary {
        if capabilities.showsResourceCounter {
            let (word, tone) = ssi?.resources.map(resourceVerdict) ?? ("Your SSI", .neutral)
            var detail = "Your SSI."
            if let res = ssi?.resources {
                detail += " Resources \(VoiceOverFormatter.dollars(res.currentCents)) of \(VoiceOverFormatter.dollars(res.limitCents))."
            }
            if let projected = ssi?.income?.projectedPaymentCents {
                detail += " Projected check about \(VoiceOverFormatter.dollars(projected))."
            }
            detail += " " + expensesLine(expensesThisMonth, expensesTotalCents, expensesImpactCents)
            return TabSummary(verdict: word == "On track" ? "Your SSI is on track" : word, detail: detail, isEstimate: true, tone: tone)
        }
        if capabilities.showsSSDILane {
            return TabSummary(
                verdict: "Your SSDI",
                detail: "Work incentives tracking for SSDI is coming in a later update. " + expensesLine(expensesThisMonth, expensesTotalCents, expensesImpactCents),
                isEstimate: true,
                tone: .neutral
            )
        }
        // No SSI, no SSDI (or not answered yet): nothing about either
        // program is shown; the only thing here is the way to change it.
        return TabSummary(
            verdict: "No benefits set up",
            detail: capabilities.benefitsUnanswered
                ? "You haven't told us about Social Security benefits yet. Answer three quick questions and this tab fills in."
                : "You told us you don't receive SSI or SSDI, so there's nothing to track here. Change that anytime in your benefits profile.",
            isEstimate: false,
            tone: .neutral
        )
    }

    static func expensesLine(_ count: Int, _ totalCents: Int, _ impactCents: Int) -> String {
        let month = DateFormatter().monthSymbols[Calendar.current.component(.month, from: Date()) - 1]
        guard count > 0 else { return "\(month): no work expenses logged yet." }
        var line = "\(month): \(VoiceOverFormatter.count(count, singular: "expense", plural: "expenses")), \(VoiceOverFormatter.dollars(totalCents))."
        if impactCents > 0 {
            line += " Worth up to \(VoiceOverFormatter.dollars(impactCents)) on your check. Estimate."
        }
        return line
    }

    // MARK: - Shared

    static func resourceVerdict(_ res: SSIResources) -> (String, ScreenReaderSummaryHeader.Tone) {
        switch res.effectiveStatus {
        case "over": return ("Over the limit", .act)
        case "critical": return ("Act now", .act)
        case "warning": return ("Watch", .watch)
        default: return ("On track", .positive)
        }
    }

    // MARK: - Magic Tap

    /// "Money header, resource status, and next due task" in one breath.
    static func magicTap(money: TabSummary, benefits: TabSummary?, nextTask: String?) -> String {
        var parts = [money.spoken]
        if let benefits { parts.append(benefits.spoken) }
        parts.append(nextTask ?? "Nothing is due right now.")
        return parts.joined(separator: " ")
    }
}

// MARK: - Accessibility preferences (Settings → Accessibility)

enum AccessibilityPrefs {
    static let hapticIntensityKey = "hapticIntensity"      // 0 off, 0.5 light, 1 normal, 1.4 strong
    static let speechVerbosityKey = "speechVerbosity"      // "brief" | "standard"

    static var hapticIntensity: Double {
        let v = UserDefaults.standard.object(forKey: hapticIntensityKey) as? Double
        return v ?? 1.0
    }

    static var isBriefSpeech: Bool {
        UserDefaults.standard.string(forKey: speechVerbosityKey) == "brief"
    }
}

extension SSIResources {
    /// v2 policy status when present, else the legacy status mapped onto
    /// the same vocabulary.
    var effectiveStatus: String {
        if let v2 = v2Status { return v2 }
        switch status {
        case "safe": return "ok"
        default: return status
        }
    }
}
