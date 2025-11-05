//
//  BankError.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Bank Error
enum BankError: LocalizedError {
    case networkError
    case unauthorized
    case validationError([ValidationErrorDetail])
    case itemNotFound
    case serverError(Int)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection error. Please check your internet connection."
        case .unauthorized:
            return "Authentication required. Please sign in again."
        case .validationError(let details):
            let errorMessages = details.map { $0.msg }.joined(separator: ", ")
            return "Validation error: \(errorMessages)"
        case .itemNotFound:
            return "Bank account or item not found."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        case .invalidResponse:
            return "Invalid response from server."
        }
    }
}

