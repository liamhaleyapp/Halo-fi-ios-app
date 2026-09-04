//
//  ReceiptOCRParser.swift
//  Halo-fi-IOS
//
//  Pure text → (amount, date, merchant, confidence) parser for receipt
//  lines recognized on device by Vision. No UI, no I/O, unit-testable.
//
//  Heuristics, in order of trust:
//  - Amount: the largest money value on a line containing "total" (but not
//    "subtotal" / "tax" / "tip"); otherwise the largest money value on the
//    receipt.
//  - Date: first line matching a known date shape (MM/DD/YYYY, YYYY-MM-DD,
//    "Sep 3, 2026", "3 Sep 2026").
//  - Merchant: the first of the top five lines that is mostly letters.
//  Confidence adds up per field; anything under `fallbackThreshold` (or a
//  missing amount) sends the image to the server-side Claude fallback.
//

import Foundation

struct ReceiptParse: Equatable {
    var amountCents: Int?
    var date: Date?
    var merchant: String?
    var confidence: Double

    /// Below this the app asks the backend extraction fallback.
    static let fallbackThreshold = 0.7

    var needsFallback: Bool {
        amountCents == nil || confidence < Self.fallbackThreshold
    }

    static let empty = ReceiptParse(amountCents: nil, date: nil, merchant: nil, confidence: 0)
}

enum ReceiptOCRParser {
    private static let moneyRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)\$?\s*(\d{1,5}(?:,\d{3})*\.\d{2})(?!\d)"#
    )
    private static let totalKeywords = ["total", "amount due", "amount paid", "balance due", "grand total", "charged", "you paid"]
    private static let notTotalKeywords = ["subtotal", "sub total", "tax", "tip", "gratuity", "change", "cash tendered", "savings"]

    private static let dateFormats: [String] = [
        "MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy",
        "yyyy-MM-dd", "MM-dd-yyyy",
        "MMM d, yyyy", "MMMM d, yyyy", "d MMM yyyy", "d MMMM yyyy",
        "MMM d yyyy", "EEE, MMM d, yyyy",
    ]
    private static let dateRegex = try! NSRegularExpression(
        pattern: #"(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}-\d{2}-\d{2}|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}|\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+\d{4})"#,
        options: [.caseInsensitive]
    )

    static func parse(lines rawLines: [String], now: Date = Date()) -> ReceiptParse {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return .empty }

        var confidence = 0.0

        // Amount
        var amountCents: Int?
        var totalLineHit = false
        for line in lines {
            let lower = line.lowercased()
            guard totalKeywords.contains(where: { lower.contains($0) }),
                  !notTotalKeywords.contains(where: { lower.contains($0) }) else { continue }
            if let cents = moneyValues(in: line).max() {
                amountCents = max(amountCents ?? 0, cents)
                totalLineHit = true
            }
        }
        if amountCents == nil {
            amountCents = lines.flatMap(moneyValues(in:)).max()
        }
        if amountCents != nil {
            confidence += totalLineHit ? 0.45 : 0.25
        }

        // Date
        var date: Date?
        for line in lines {
            if let d = parseDate(in: line, now: now) {
                date = d
                confidence += 0.3
                break
            }
        }

        // Merchant
        var merchant: String?
        for line in lines.prefix(5) {
            if looksLikeMerchant(line) {
                merchant = line
                confidence += 0.25
                break
            }
        }

        return ReceiptParse(
            amountCents: amountCents,
            date: date,
            merchant: merchant,
            confidence: min(1.0, confidence)
        )
    }

    // MARK: - Pieces

    static func moneyValues(in line: String) -> [Int] {
        let ns = line as NSString
        return moneyRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let raw = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
            guard let value = Double(raw) else { return nil }
            return Int((value * 100).rounded())
        }
    }

    static func parseDate(in line: String, now: Date) -> Date? {
        let ns = line as NSString
        guard let m = dateRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let candidate = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ".", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in dateFormats {
            formatter.dateFormat = format
            if let d = formatter.date(from: candidate) {
                // Receipts are in the past and within a year; anything else is
                // more likely a serial number or an expiry.
                let future = d.timeIntervalSince(now) > 2 * 24 * 3600
                let ancient = now.timeIntervalSince(d) > 400 * 24 * 3600
                if !future && !ancient { return d }
            }
        }
        return nil
    }

    static func looksLikeMerchant(_ line: String) -> Bool {
        let letters = line.filter { $0.isLetter }.count
        let digits = line.filter { $0.isNumber }.count
        guard line.count >= 3, line.count <= 40, letters >= 3, digits <= 2 else { return false }
        let lower = line.lowercased()
        let banned = ["receipt", "invoice", "thank", "welcome", "order", "total", "customer", "copy", "www.", "http", "tel", "phone"]
        return !banned.contains(where: { lower.contains($0) })
    }
}
