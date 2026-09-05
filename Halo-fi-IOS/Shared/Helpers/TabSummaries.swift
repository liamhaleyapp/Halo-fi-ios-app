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
    /// The one line drawn under the hero figure (the figure itself already
    /// shows the first sentence of `detail`). Explicit, so adding a
    /// sentence to `detail` never silently changes what is visible.
    var subline: String? = nil
    /// The short line DRAWN under the verdict on a tab header when `detail`
    /// is long. Spoken output always uses `detail`.
    var visual: String? = nil

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

        var sublines: [String] = []

        // The balance is the headline for everyone. For SSI users the same
        // card also carries the resource counter (Liam, 2026-09-04): the
        // countable figure against the limit, in words before numbers, and
        // the card opens the Resource monitor.
        verdict = s.accountCount == 0 ? "No accounts linked" : "Balance"
        let accounts = VoiceOverFormatter.count(s.accountCount, singular: "account", plural: "accounts")
        detail = "Cash \(VoiceOverFormatter.dollars(s.cashCents)) across \(accounts). Owed \(VoiceOverFormatter.dollars(s.owedCents))."
        tone = s.owedCents > s.cashCents ? .watch : .positive

        if capabilities.showsResourceCounter, let res = s.resources {
            let (state, t) = resourceState(res)
            tone = t
            isEstimate = true
            var line = "Counts toward your SSI limit: \(VoiceOverFormatter.dollars(res.currentCents)) of \(VoiceOverFormatter.dollars(res.limitCents)), \(state)."
            if let days = res.daysUntilMeasurement, res.effectiveStatus != "ok" {
                line += " Social Security measures in \(days == 1 ? "1 day" : "\(days) days")."
            }
            detail += " " + line
            // The gauge already draws the counted figure; the only drawn
            // sentence is the forward number (2026-09-05), one line. The
            // possible-bill note is spoken and lives on the monitor.
            if let proj = res.projection {
                let forward = "By \(spokenDate(proj.measurementDateIso)), about \(VoiceOverFormatter.dollars(proj.projectedCents)) of \(VoiceOverFormatter.dollars(proj.limitCents)), \(proj.stateWords)."
                detail += " " + forward
                if proj.unconfirmedBillCount > 0 {
                    detail += " \(VoiceOverFormatter.count(proj.unconfirmedBillCount, singular: "possible bill", plural: "possible bills")) not counted yet."
                }
                sublines.append(forward)
            }
        }
        if s.connectionsNeedingAttention > 0 {
            let line = "\(VoiceOverFormatter.count(s.connectionsNeedingAttention, singular: "connection", plural: "connections")) need\(s.connectionsNeedingAttention == 1 ? "s" : "") attention."
            detail += " " + line
            sublines.append(line)
        }
        return TabSummary(verdict: verdict, detail: detail, isEstimate: isEstimate, tone: tone,
                          subline: sublines.isEmpty ? nil : sublines.joined(separator: " "))
    }

    /// The budget summary row under the Money header.
    static func budgetRow(_ s: MoneySnapshot) -> String {
        guard let total = s.budgetTotal else {
            return "No budget yet. Spent \(VoiceOverFormatter.dollars(s.spentCents)) this month."
        }
        var line = "Spent \(VoiceOverFormatter.dollars(total.spentCents)) of \(VoiceOverFormatter.dollars(total.limitCents))."
        if let over = s.firstOverCategory { line += " Over in \(over)." }
        return line
    }

    // MARK: - Benefits

    /// The Benefits header leads with the MOST URGENT item (Liam,
    /// 2026-09-04): over the limit > act now > package due > receipts still
    /// needed > resources in the watch band > the plain lane line.
    static func benefits(
        capabilities: UserCapabilities,
        ssi: SSIStatus?,
        expensesThisMonth: Int,
        expensesTotalCents: Int,
        expensesImpactCents: Int,
        reminders: [SSIReminder] = [],
        needsReceiptCount: Int = 0
    ) -> TabSummary {
        let expenses = expensesLine(expensesThisMonth, expensesTotalCents, expensesImpactCents)
        let packageDue = reminders.first { $0.kind == "submit_package" }
        let receipts: String? = needsReceiptCount > 0
            ? "\(VoiceOverFormatter.count(needsReceiptCount, singular: "receipt", plural: "receipts")) still needed"
            : nil

        if capabilities.showsResourceCounter {
            let res = ssi?.resources
            let status = res?.effectiveStatus ?? "ok"
            var projected = ""
            if let p = ssi?.income?.projectedPaymentCents {
                projected = " Projected check about \(VoiceOverFormatter.dollars(p))."
            }
            let resourcesLine: String = res.map {
                "Resources \(VoiceOverFormatter.dollars($0.currentCents)) of \(VoiceOverFormatter.dollars($0.limitCents))."
            } ?? ""
            let measures: String = {
                guard let days = res?.daysUntilMeasurement, status != "ok" else { return "" }
                return " Social Security measures in \(days == 1 ? "1 day" : "\(days) days")."
            }()

            // Drawn line: one short sentence; the full detail is spoken.
            let resourcesShort = (resourcesLine + measures).trimmingCharacters(in: .whitespaces)
            if status == "over" {
                return TabSummary(verdict: "Over the SSI resource limit", detail: "\(resourcesLine)\(measures)\(projected) \(expenses)", isEstimate: true, tone: .act, visual: resourcesShort)
            }
            if status == "critical" {
                return TabSummary(verdict: "Act now on resources", detail: "\(resourcesLine)\(measures)\(projected) \(expenses)", isEstimate: true, tone: .act, visual: resourcesShort)
            }
            if let packageDue {
                return TabSummary(verdict: "Monthly package due", detail: "\(packageDue.body) Your SSI. \(resourcesLine) \(expenses)", isEstimate: true, tone: .watch, visual: packageLine(packageDue))
            }
            if let receipts {
                return TabSummary(verdict: receipts, detail: "Your SSI. \(resourcesLine) \(expenses)", isEstimate: true, tone: .watch, visual: "Attach them under Work expenses.")
            }
            if status == "warning" {
                return TabSummary(verdict: "Resources getting close", detail: "\(resourcesLine)\(measures)\(projected) \(expenses)", isEstimate: true, tone: .watch, visual: resourcesShort)
            }
            let detail = ("Your SSI. " + resourcesLine + projected + " " + expenses).replacingOccurrences(of: "  ", with: " ")
            return TabSummary(verdict: "Your SSI is on track", detail: detail, isEstimate: true, tone: .positive, visual: resourcesLine.isEmpty ? nil : resourcesLine)
        }
        if capabilities.showsSSDILane {
            if let packageDue {
                return TabSummary(verdict: "Monthly package due", detail: "\(packageDue.body) Your SSDI. \(expenses)", isEstimate: true, tone: .watch, visual: packageLine(packageDue))
            }
            if let receipts {
                return TabSummary(verdict: receipts, detail: "Your SSDI. \(expenses)", isEstimate: true, tone: .watch, visual: "Attach them under Work expenses.")
            }
            // The "work incentives coming later" note is the card below the
            // header; the header says it once, not twice (2026-09-05).
            return TabSummary(verdict: "Your SSDI", detail: expenses, isEstimate: true, tone: .neutral, visual: expensesShortLine(expensesThisMonth, expensesTotalCents))
        }
        // Not answered yet: nothing about either program is shown; the only
        // thing on the tab is the way to start. (Answered "no SSI, no SSDI"
        // users have no Benefits tab at all.)
        return TabSummary(
            verdict: "No benefits set up",
            detail: "You haven't told us about your Social Security benefits yet. A short questionnaire sets this tab up for you.",
            isEstimate: false,
            tone: .neutral
        )
    }

    /// The drawn version of `expensesLine`: count and total only.
    static func expensesShortLine(_ count: Int, _ totalCents: Int) -> String {
        let month = DateFormatter().monthSymbols[Calendar.current.component(.month, from: Date()) - 1]
        guard count > 0 else { return "\(month): none logged yet." }
        return "\(month): \(VoiceOverFormatter.count(count, singular: "expense", plural: "expenses")), \(VoiceOverFormatter.dollars(totalCents))."
    }

    /// "August package is ready. Due by September 6." — the drawn line for
    /// a submit reminder; the reminder body is spoken.
    static func packageLine(_ reminder: SSIReminder) -> String {
        var line = "\(monthName(reminder.month)) package is ready."
        if let due = reminder.dueOn { line += " Due by \(spokenDate(due))." }
        return line
    }

    static func monthName(_ key: String?) -> String {
        guard let key, key.count >= 7, let m = Int(key.dropFirst(5).prefix(2)), (1...12).contains(m) else { return "Last month's" }
        return DateFormatter().monthSymbols[m - 1]
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

    static func spokenDate(_ iso: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMMM d"; return out.string(from: d)
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

    /// The same bands as `resourceVerdict`, as a phrase that reads inside a
    /// sentence ("…of 2,000 dollars, getting close.").
    static func resourceState(_ res: SSIResources) -> (String, ScreenReaderSummaryHeader.Tone) {
        switch res.effectiveStatus {
        case "over": return ("over the limit", .act)
        case "critical": return ("act now", .act)
        case "warning": return ("getting close", .watch)
        default: return ("on track", .positive)
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
