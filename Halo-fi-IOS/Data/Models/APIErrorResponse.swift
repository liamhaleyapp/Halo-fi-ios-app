//
//  APIErrorResponse.swift
//  Halo-fi-IOS
//
//  Generic API error response model for parsing server errors.
//  Handles the common {"success": false, "error": "..."} format.
//

import Foundation

/// API error response with success flag and error/message fields.
/// Used by NetworkService to parse error responses from the server.
struct APIErrorResponse: Codable {
    let success: Bool?
    let error: String?
    let message: String?

    /// Returns the error message, preferring "error" over "message".
    var errorMessage: String? {
        error ?? message
    }
}
