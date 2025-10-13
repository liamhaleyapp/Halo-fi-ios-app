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
    case serverError(Int)
    case tokenExpired
    
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
        case .serverError(let code):
            return "Server error (\(code)). Please try again"
        case .tokenExpired:
            return "Your session has expired. Please sign in again"
        }
    }
}

struct ValidationError: Codable {
  let detail: [ValidationErrorDetail]
}

struct ValidationErrorDetail: Codable {
  let loc: [String]
  let msg: String
  let type: String
}
