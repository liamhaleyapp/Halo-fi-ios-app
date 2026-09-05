//
//  TransactionNameFormatter.swift
//  Halo-fi-IOS
//
//  Banks ship raw ACH descriptors ("ORIG CO NAME:GARNALTD ORIG ID:1371913769
//  DESC DATE:260807 CO ENTRY DESCR:Garna LTD SEC:PPD TRACE#:…"). Nobody
//  should read that, least of all through VoiceOver (Liam, 2026-09-05).
//  One cleaner for every place a transaction name is shown; the detail
//  screen still shows the raw text under "Bank description".
//

import Foundation

enum TransactionNameFormatter {
    static let maxLength = 40

    /// Merchant when Plaid has one, otherwise the cleaned bank name.
    static func display(name: String, merchant: String?) -> String {
        if let merchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines), !merchant.isEmpty, !looksLikeDescriptor(merchant) {
            return truncate(tidyCase(merchant))
        }
        return truncate(clean(name))
    }

    /// Strip ACH / card-processor noise from a bank description.
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "Transaction" }

        // ACH: prefer the entry description (what the payer calls it), then
        // the originator name.
        if let entry = capture(#"CO ENTRY DESCR:\s*([^:]*?)\s*(?:SEC:|TRACE#|EED:|IND ID|IND NAME|TRN:|$)"#, in: text), !entry.isEmpty {
            text = entry
        } else if let orig = capture(#"ORIG CO NAME:\s*([^:]*?)\s*(?:ORIG ID:|DESC DATE:|CO ENTRY|SEC:|$)"#, in: text), !orig.isEmpty {
            text = orig
        } else {
            // Cut at common tails: "PPD ID: …", "WEB ID …", "CCD …", "TRACE#…", "REF #…"
            for tail in [#"\s+(PPD|CCD|WEB|ARC|TEL|POS)\s*ID[:#]?.*$"#, #"\s+TRACE#.*$"#, #"\s+REF\s*#?.*$"#, #"\s+ID:\s*\S+.*$"#, #"\s+DES:.*$"#] {
                text = text.replacingOccurrences(of: tail, with: "", options: [.regularExpression, .caseInsensitive])
            }
            // Long digit / reference runs and card-processor prefixes.
            text = text.replacingOccurrences(of: #"\b[A-Z0-9]*\d{5,}[A-Z0-9]*\b"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\b(X{3,}\d*|TST\*|SQ \*|SP \*|PAYPAL \*|PP\*|DD \*)"#, with: "", options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: #"\*"#, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -:,.#"))
        return text.isEmpty ? "Transaction" : truncate(tidyCase(text))
    }

    /// ALL CAPS reads as shouting and VoiceOver spells acronyms; keep
    /// mixed-case text as is, title-case shouted text (short tokens like
    /// "LTD", "LLC", "ATM" stay upper).
    static func tidyCase(_ text: String) -> String {
        let letters = text.filter { $0.isLetter }
        guard !letters.isEmpty, letters.allSatisfy({ $0.isUppercase }) else { return text }
        let keep: Set<String> = ["LTD", "LLC", "INC", "ATM", "USA", "IRS", "SSA", "TD", "PNC", "CVS", "ACH", "DBA", "PPD", "UPS", "USPS", "AT&T"]
        return text.split(separator: " ").map { word -> String in
            let w = String(word)
            if keep.contains(w) || w.count <= 2 { return w }
            return w.prefix(1).uppercased() + w.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    private static func looksLikeDescriptor(_ s: String) -> Bool {
        s.range(of: #"ORIG CO NAME:|CO ENTRY DESCR:|TRACE#"#, options: .regularExpression) != nil
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespaces)
    }

    private static func truncate(_ s: String) -> String {
        s.count > maxLength ? String(s.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…" : s
    }
}

extension Transaction {
    /// What to show and speak for this transaction.
    var displayName: String { TransactionNameFormatter.display(name: name, merchant: merchantName) }
}
