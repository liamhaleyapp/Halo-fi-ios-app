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
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network error. Please try again"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}
