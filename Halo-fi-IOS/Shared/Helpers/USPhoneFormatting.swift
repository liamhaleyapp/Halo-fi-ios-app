//
//  USPhoneFormatting.swift
//  Halo-fi-IOS
//
//  US phone number formatting and validation utilities.
//  Named explicitly "US" to prevent misuse for international numbers.
//

import Foundation

enum USPhoneFormatting {

    // MARK: - Validation Result

    enum ValidationResult {
        case valid(normalizedDigits: String)
        case tooShort
        case tooLong
        case invalidElevenDigit  // 11 digits but doesn't start with "1"
        case empty
    }

    // MARK: - Digit Extraction

    /// Extracts only digit characters from a phone number string.
    /// Handles all formatting: parentheses, dashes, spaces, +, etc.
    /// - Parameter phoneNumber: Raw phone number input (may contain formatting)
    /// - Returns: String containing only digits
    static func extractDigits(from phoneNumber: String) -> String {
        phoneNumber.filter { $0.isNumber }
    }

    // MARK: - Validation

    /// Validates and normalizes a US phone number to 10 digits.
    /// - Parameter phoneNumber: Raw phone number input (may include formatting like +1, dashes, etc.)
    /// - Returns: ValidationResult indicating success with normalized digits, or specific failure reason
    ///
    /// Rules:
    /// - Strips all non-digit characters first
    /// - 10 digits: Valid as-is
    /// - 11 digits starting with "1": Strip the leading "1" (US country code), valid
    /// - 11 digits NOT starting with "1": Invalid (not a US number)
    /// - Less than 10 digits: Too short
    /// - More than 11 digits: Too long
    static func validate(_ phoneNumber: String) -> ValidationResult {
        let digits = extractDigits(from: phoneNumber)

        guard !digits.isEmpty else {
            return .empty
        }

        switch digits.count {
        case 0..<10:
            return .tooShort
        case 10:
            return .valid(normalizedDigits: digits)
        case 11:
            if digits.hasPrefix("1") {
                // Strip the leading "1" (US country code)
                let normalized = String(digits.dropFirst())
                return .valid(normalizedDigits: normalized)
            } else {
                // 11 digits not starting with 1 = not a valid US number
                return .invalidElevenDigit
            }
        default:
            return .tooLong
        }
    }

    // MARK: - API Formatting

    /// Formats a phone number for API requests (E.164 format for US: +1XXXXXXXXXX).
    /// - Parameter phoneNumber: Raw phone number input
    /// - Returns: Formatted phone number with +1 prefix, or nil if invalid
    static func formatForAPI(_ phoneNumber: String) -> String? {
        switch validate(phoneNumber) {
        case .valid(let normalizedDigits):
            return "+1" + normalizedDigits
        case .tooShort, .tooLong, .invalidElevenDigit, .empty:
            return nil
        }
    }

    // MARK: - Error Messages

    /// Returns a user-friendly error message for validation failures.
    /// - Parameter result: The validation result
    /// - Returns: Error message string, or nil if valid
    static func errorMessage(for result: ValidationResult) -> String? {
        switch result {
        case .valid:
            return nil
        case .empty:
            return "Phone number is required."
        case .tooShort:
            return "Phone number must be at least 10 digits."
        case .tooLong:
            return "Phone number is too long."
        case .invalidElevenDigit:
            return "Invalid US phone number format."
        }
    }
}
