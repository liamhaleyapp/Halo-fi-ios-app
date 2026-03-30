//
//  DateFormatting.swift
//  Halo-fi-IOS
//
//  Centralized date formatting utilities.
//  Replaces scattered date formatting logic across the codebase.
//

import Foundation

enum DateFormatting {

    // MARK: - Cached Formatters

    /// ISO8601 formatter for API requests (full date-time with fractional seconds).
    private static let iso8601Full: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO8601 formatter for date-only values.
    private static let iso8601DateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    /// Display formatter for transaction dates (e.g., "Dec 10, 2025").
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Short display formatter (e.g., "12/10/25").
    private static let shortDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    /// Formatter for parsing API date strings (yyyy-MM-dd).
    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Formatter for parsing API datetime strings.
    private static let apiDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Formatting for API Requests

    /// Formats a date for API requests (ISO8601 with fractional seconds).
    /// - Parameter date: The date to format.
    /// - Returns: ISO8601 formatted string.
    static func formatForAPI(_ date: Date) -> String {
        iso8601Full.string(from: date)
    }

    /// Formats a date for API requests (date only, no time).
    /// - Parameter date: The date to format.
    /// - Returns: ISO8601 date-only string (e.g., "2025-12-10").
    static func formatDateOnlyForAPI(_ date: Date) -> String {
        iso8601DateOnly.string(from: date)
    }

    /// Formats an optional date for API requests.
    /// - Parameter date: The optional date to format.
    /// - Returns: Formatted string or nil if date is nil.
    static func formatForAPI(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        return formatDateOnlyForAPI(date)
    }

    // MARK: - Formatting for Display

    /// Formats a date for display (e.g., "Dec 10, 2025").
    /// - Parameter date: The date to format.
    /// - Returns: Human-readable date string.
    static func formatForDisplay(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    /// Formats a date for short display (e.g., "12/10/25").
    /// - Parameter date: The date to format.
    /// - Returns: Short date string.
    static func formatShort(_ date: Date) -> String {
        shortDisplayFormatter.string(from: date)
    }

    /// Smart date formatter for transaction lists.
    /// Shows "Today", "Yesterday" for recent, "Mar 27" for this year,
    /// "Feb 15, 2025" for older years.
    static func formatSmart(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let now = Date()
        let daysDiff = calendar.dateComponents([.day], from: date, to: now).day ?? 0

        // Within last 6 days: "Monday", "Tuesday", etc.
        if daysDiff <= 6 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }

        // Same year: "Mar 27"
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }

        // Different year: "Feb 15, 2025"
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    /// Parses a date string and returns a smart-formatted string.
    static func parseAndFormatSmart(_ dateString: String) -> String {
        guard let date = parse(dateString) else {
            return dateString
        }
        return formatSmart(date)
    }

    // MARK: - Parsing

    /// Parses a date string from the API.
    /// Tries multiple formats to handle inconsistent API responses.
    /// - Parameter dateString: The date string to parse.
    /// - Returns: Parsed Date or nil if parsing fails.
    static func parse(_ dateString: String) -> Date? {
        // Try ISO8601 with fractional seconds first
        if let date = iso8601Full.date(from: dateString) {
            return date
        }

        // Try ISO8601 date only
        if let date = iso8601DateOnly.date(from: dateString) {
            return date
        }

        // Try yyyy-MM-dd format
        if let date = apiDateFormatter.date(from: dateString) {
            return date
        }

        // Try yyyy-MM-dd'T'HH:mm:ss format
        if let date = apiDateTimeFormatter.date(from: dateString) {
            return date
        }

        // Handle date strings with timezone offset
        let trimmed = dateString.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression)
        if let date = apiDateTimeFormatter.date(from: trimmed) {
            return date
        }

        return nil
    }

    /// Parses a date string and returns a display-formatted string.
    /// - Parameter dateString: The date string to parse.
    /// - Returns: Display-formatted string or the original string if parsing fails.
    static func parseAndFormat(_ dateString: String) -> String {
        guard let date = parse(dateString) else {
            return dateString
        }
        return formatForDisplay(date)
    }
}
