//
//  PlaidError.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

enum PlaidError: Error, LocalizedError {
  case linkTokenCreationFailed
  case publicTokenExchangeFailed
  case userCancelled
  case networkError
  
  var errorDescription: String? {
    switch self {
    case .linkTokenCreationFailed:
      return "Failed to create secure connection"
    case .publicTokenExchangeFailed:
      return "Failed to complete bank connection"
    case .userCancelled:
      return "Bank connection was cancelled"
    case .networkError:
      return "Network error. Please try again"
    }
  }
}
