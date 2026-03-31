//
//  SubscriptionService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation
import RevenueCat
import StoreKit
import SwiftUI

@Observable
@MainActor
class SubscriptionService {
  // Current subscription status
  var currentSubscription: SubscriptionStatus = .none
  var activeEntitlements: Set<String> = []
  var customerInfo: CustomerInfo?
  var isLoading = false
  var pendingPlanChange: String?
  
  // Available products
  var availablePackages: [Package] = []
  var availableProducts: [StoreProduct] = []
  
  init() {
    // Public initializer for dependency injection
  }
  
  // MARK: - Initialization
  
  func initialize() async {
    isLoading = true
    
    do {
      // Fetch available products
      try await fetchProducts()
      
      // Get customer info
      await checkSubscriptionStatus()
      
      isLoading = false
    } catch {
      isLoading = false
    }
  }
  
  // MARK: - Product Fetching
  
  private func fetchProducts() async throws {
    let offerings = try await Purchases.shared.offerings()
    
    guard let currentOffering = offerings.current else {
      return
    }
    
    // Get available packages
    availablePackages = currentOffering.availablePackages
    
    // Get store products
    availableProducts = availablePackages.compactMap { $0.storeProduct }
  }
  
  // MARK: - Subscription Status
  
  func checkSubscriptionStatus() async {
    do {
      customerInfo = try await Purchases.shared.customerInfo()
      
      // Update entitlements — only track active ones
      if let entitlements = customerInfo?.entitlements.all {
        activeEntitlements = Set(
          entitlements.filter { $0.value.isActive }.map { $0.key }
        )
      } else {
        activeEntitlements = []
      }

      // Determine subscription status
      if activeEntitlements.isEmpty {
        // Check if they had entitlements before (expired) vs never subscribed
        if let entitlements = customerInfo?.entitlements.all, !entitlements.isEmpty {
          currentSubscription = .expired
        } else {
          currentSubscription = .none
        }
      } else {
        let hasMax = activeEntitlements.contains(where: {
          $0.lowercased().contains("max")
        })
        let hasPro = activeEntitlements.contains(where: {
          $0.lowercased().contains("pro") && !$0.lowercased().contains("max")
        })
        let hasBasic = activeEntitlements.contains(where: {
          $0.lowercased().contains("basic") && !$0.lowercased().contains("pro") && !$0.lowercased().contains("max")
        })

        if hasMax {
          currentSubscription = .max
        } else if hasPro {
          currentSubscription = .pro
        } else if hasBasic {
          currentSubscription = .basic
        } else {
          currentSubscription = .active
        }
      }
    } catch {
      currentSubscription = .none
    }

    await checkPendingPlanChange()
  }

  // MARK: - Purchase Methods
  
  func purchase(package: Package) async throws -> (success: Bool, customerInfo: CustomerInfo?) {
    isLoading = true
    
    defer {
      Task { @MainActor in
        isLoading = false
      }
    }
    
    do {
      let purchaseResult = try await Purchases.shared.purchase(package: package)
      
      // Check if user cancelled
      if purchaseResult.userCancelled {
        throw SubscriptionError.purchaseCancelled
      }
      
      // Update local state
      self.customerInfo = purchaseResult.customerInfo
      await checkSubscriptionStatus()
      
      return (true, purchaseResult.customerInfo)
    } catch let error as ErrorCode {
      // Handle "already subscribed" — auto-restore instead of showing error
      if error == .productAlreadyPurchasedError {
        try await restorePurchases()
        if hasActiveSubscription {
          return (true, customerInfo)
        }
      }
      throw SubscriptionError.purchaseFailed(error.localizedDescription)
    } catch {
      // Re-throw our custom errors
      if error is SubscriptionError {
        throw error
      }
      throw SubscriptionError.purchaseFailed(error.localizedDescription)
    }
  }
  
  func purchase(productId: String) async throws -> (success: Bool, customerInfo: CustomerInfo?) {
    guard let package = availablePackages.first(where: { $0.storeProduct.productIdentifier == productId }) else {
      throw SubscriptionError.productNotFound
    }
    
    return try await purchase(package: package)
  }
  
  // MARK: - Restore Purchases
  
  func restorePurchases() async throws {
    isLoading = true
    
    defer {
      Task { @MainActor in
        isLoading = false
      }
    }
    
    do {
      customerInfo = try await Purchases.shared.restorePurchases()
      
      // Update local state
      await checkSubscriptionStatus()
    } catch {
      throw SubscriptionError.restoreFailed(error.localizedDescription)
    }
  }
  
  // MARK: - Subscription Management
  
  func checkIntroEligibility(productId: String) async -> Bool {
    do {
      let offerings = try await Purchases.shared.offerings()
      guard offerings.current?.availablePackages.first(where: { $0.storeProduct.productIdentifier == productId }) != nil else {
        return false
      }
      
      // checkTrialOrIntroDiscountEligibility uses async/await pattern
      // Using the new productIdentifiers: parameter to avoid deprecation warning
      let eligibilityMap = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: [productId])
      let status = eligibilityMap[productId]?.status
      return status == .eligible
    } catch {
      return false
    }
  }
  
  // Get renewal date for current subscription
  var renewalDate: Date? {
    guard let entitlements = customerInfo?.entitlements.all.values.first(where: { $0.isActive }) else {
      return nil
    }
    return entitlements.expirationDate
  }

  // Check if subscription is active
  var hasActiveSubscription: Bool {
    currentSubscription != .none && currentSubscription != .expired
  }


  // Check StoreKit 2 renewal info for a pending plan change
  func checkPendingPlanChange() async {
    guard let activeEntitlement = customerInfo?.entitlements.all.values.first(where: { $0.isActive }) else {
      pendingPlanChange = nil
      return
    }

    let currentProductId = activeEntitlement.productIdentifier

    do {
      let products = try await Product.products(for: [currentProductId])
      guard let product = products.first else {
        pendingPlanChange = nil
        return
      }

      let statuses = try await product.subscription?.status ?? []
      for status in statuses {
        guard case .verified(let renewalInfo) = status.renewalInfo else { continue }

        if let autoRenewProductId = renewalInfo.autoRenewPreference,
           autoRenewProductId != currentProductId {
          pendingPlanChange = planDisplayName(from: autoRenewProductId)
          return
        }
      }
    } catch {
      Logger.error("Failed to check pending plan change: \(error)")
    }

    pendingPlanChange = nil
  }

  private func planDisplayName(from productId: String) -> String {
    let id = productId.lowercased()
    let tier: String
    if id.contains("max") { tier = "Max" }
    else if id.contains("pro") { tier = "Pro" }
    else if id.contains("basic") { tier = "Basic" }
    else { tier = "Unknown" }

    let cycle = id.contains("yearly") ? "Yearly" : "Monthly"
    return "\(tier) \(cycle)"
  }

  // MARK: - Clear Cached State

  /// Clears locally cached subscription state
  /// Call this when user signs out to ensure fresh state on next login
  func clearCachedState() {
    currentSubscription = .none
    activeEntitlements = []
    customerInfo = nil
    pendingPlanChange = nil
    // Note: We don't clear availablePackages/availableProducts as they're not user-specific
  }
}

// MARK: - Supporting Types

enum SubscriptionStatus {
  case none
  case basic
  case pro
  case max
  case active  // Generic active subscription
  case expired
  
  var displayName: String {
    switch self {
    case .none: return "None"
    case .basic: return "Basic"
    case .pro: return "Pro"
    case .max: return "Max"
    case .active: return "Active"
    case .expired: return "Expired"
    }
  }
}

enum SubscriptionError: LocalizedError {
  case purchaseCancelled
  case productNotFound
  case productUnavailable
  case purchaseFailed(String)
  case restoreFailed(String)
  case unknown
  
  var errorDescription: String? {
    switch self {
    case .purchaseCancelled:
      return "Purchase was cancelled"
    case .productNotFound:
      return "Product not found"
    case .productUnavailable:
      return "Product is not available at this time"
    case .purchaseFailed(let message):
      return "Purchase failed: \(message)"
    case .restoreFailed(let message):
      return "Restore failed: \(message)"
    case .unknown:
      return "An unknown error occurred"
    }
  }
}

extension SubscriptionService {
  static var previewActivePro: SubscriptionService {
    let service = SubscriptionService()
    
    // Fake a Pro subscription
    service.currentSubscription = .pro
    service.activeEntitlements = ["pro"]
    service.customerInfo = nil
    service.isLoading = false
    service.availablePackages = []
    service.availableProducts = []
    
    return service
  }
  
  static var previewNone: SubscriptionService {
    let service = SubscriptionService()
    service.currentSubscription = .none
    service.activeEntitlements = []
    service.isLoading = false
    return service
  }
}
