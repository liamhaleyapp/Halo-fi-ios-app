//
//  VoiceOverFormatter.swift
//  Halo-fi-IOS
//
//  Phase 11 Track C — single source of truth for VoiceOver-
//  friendly money strings. The visible UI keeps using
//  BudgetFormatter ("$994.00"); accessibility labels use this
//  helper ("994 dollars") so VoiceOver doesn't speak the
//  trailing ".00" as "point zero zero".
//
//  Rules:
//    - Whole dollars only — strip the cents part since rounded
//      decimals sound terrible read aloud.
//    - Singular vs plural ("1 dollar" vs "5 dollars") so the
//      synthesizer doesn't say "1 dollars".
//    - Comma grouping for readability when spoken slowly.
//

import Foundation

enum VoiceOverFormatter {

    /// Whole-dollar speech form for an integer-cent amount.
    /// Negative inputs floor at $0.
    static func dollars(_ cents: Int) -> String {
        let safe = max(0, cents)
        let dollars = Int((Double(safe) / 100.0).rounded())
        if dollars == 1 { return "1 dollar" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        let number = formatter.string(from: NSNumber(value: dollars)) ?? "\(dollars)"
        return "\(number) dollars"
    }

    /// "1 deduction" / "3 deductions" — generic singular/plural.
    static func count(_ n: Int, singular: String, plural: String) -> String {
        n == 1 ? "\(n) \(singular)" : "\(n) \(plural)"
    }
}
