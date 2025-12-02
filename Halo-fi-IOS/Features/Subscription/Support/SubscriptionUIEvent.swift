//
//  SubscriptionUIEvent.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/1/25.
//

import Foundation

enum SubscriptionUIEvent: Equatable, Identifiable {
  case purchase(message: String)
  case restore(message: String)
  case info(message: String)
  
  var id: String {
    switch self {
    case .purchase(let message): return "purchase-\(message)"
    case .restore(let message):  return "restore-\(message)"
    case .info(let message):     return "info-\(message)"
    }
  }
}
