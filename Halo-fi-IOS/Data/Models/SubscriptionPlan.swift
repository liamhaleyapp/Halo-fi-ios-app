//
//  SubscriptionPlan.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/18/25.
//
import Foundation

enum SubscriptionPlan: CaseIterable {
  case basic, pro, max
  
  var displayName: String {
    switch self {
    case .basic: return "Basic"
    case .pro: return "Pro"
    case .max: return "Max"
    }
  }
  
  var iconName: String {
    switch self {
    case .basic: return "star.fill"
    case .pro: return "star.circle.fill"
    case .max: return "crown.fill"
    }
  }
  
  var description: String {
    switch self {
    case .basic: return "20 mins voice convo / No instant refresh"
    case .pro: return "45 mins convo / 5 instant account refreshes"
    case .max: return "120 mins convo / 15 instant refreshes"
    }
  }
  
  var monthlyPrice: String {
    switch self {
    case .basic: return "$12.99/mo"
    case .pro: return "$24.99/mo"
    case .max: return "$49.99/mo"
    }
  }
  
  var yearlyPrice: String {
    switch self {
    case .basic: return "$144.99/yr"
    case .pro: return "$274.99/yr"
    case .max: return "$549.99/yr"
    }
  }
  
  // RevenueCat Product IDs
  var monthlyProductId: String {
    switch self {
    case .basic: return "com.halofi.basic.monthly"
    case .pro: return "com.halofi.pro.monthly"
    case .max: return "com.halofi.max.monthly"
    }
  }
  
  var yearlyProductId: String {
    switch self {
    case .basic: return "com.halofi.basic.yearly"
    case .pro: return "com.halofi.pro.yearly"
    case .max: return "com.halofi.max.yearly"
    }
  }
  
  func productId(for billingCycle: BillingCycle) -> String {
    switch billingCycle {
    case .monthly: return monthlyProductId
    case .yearly: return yearlyProductId
    }
  }
}

enum BillingCycle {
  case monthly, yearly
}
