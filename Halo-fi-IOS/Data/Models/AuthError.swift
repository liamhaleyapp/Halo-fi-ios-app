//
//  AuthError.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

enum AuthError: LocalizedError {
    case invalidCredentials
    case networkError
    case unknownError
    case validationError([ValidationErrorDetail])
    case emailAlreadyExists
    case serverError(Int, String?)
    case tokenExpired
    case notAuthenticated
    case invalidResponse
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network error. Please try again"
        case .unknownError:
            return "An unknown error occurred"
        case .validationError(let details):
            let messages = details.map { $0.msg }.joined(separator: ", ")
            return "Validation error: \(messages)"
        case .emailAlreadyExists:
            return "An account with this email already exists"
        case .serverError(let code, let detail):
            if let detail = detail, !detail.isEmpty {
                return detail
            }
            return "Server error (\(code)). Please try again"
        case .tokenExpired:
            return "Your session has expired. Please sign in again"
        case .notAuthenticated:
            return "You must be signed in to perform this action"
        case .invalidResponse:
            return "Invalid response from server"
        case .notImplemented:
            return "This feature is not yet implemented"
        }
    }
}

struct ValidationError: Codable {
  let detail: [ValidationErrorDetail]
}

// Simple error response with a string detail (e.g., {"detail": "Invalid phone number format"})
struct SimpleErrorResponse: Codable {
  let detail: String
}

struct ValidationErrorDetail: Codable {
  let loc: [String]
  let msg: String
  let type: String
}
