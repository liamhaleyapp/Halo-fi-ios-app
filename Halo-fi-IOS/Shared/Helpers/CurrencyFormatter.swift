//
//  CurrencyFormatter.swift
//  Halo-fi-IOS
//
//  Centralized currency formatting utility.
//  Replaces duplicate formatCurrency functions across the codebase.
//

import Foundation

enum CurrencyFormatter {

    // MARK: - Cached Formatter

    /// Cached NumberFormatter for performance.
    /// NumberFormatter is expensive to create, so we reuse a single instance.
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter
    }()

    // MARK: - Public API

    /// Formats a monetary amount with the specified currency.
    /// - Parameters:
    ///   - amount: The monetary amount to format.
    ///   - currency: ISO 4217 currency code (e.g., "USD", "EUR"). Defaults to "USD".
    /// - Returns: A formatted currency string (e.g., "$1,234.56").
    static func format(_ amount: Double, currency: String = "USD") -> String {
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(String(format: "%.2f", amount))"
    }

    /// Formats a monetary amount for accessibility labels.
    /// - Parameters:
    ///   - amount: The monetary amount to format.
    ///   - currency: ISO 4217 currency code. Defaults to "USD".
    /// - Returns: A string suitable for VoiceOver (e.g., "1,234 dollars and 56 cents").
    static func formatForAccessibility(_ amount: Double, currency: String = "USD") -> String {
        formatter.currencyCode = currency
        formatter.numberStyle = .currencyPlural
        let result = formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
        formatter.numberStyle = .currency
        return result
    }
}
