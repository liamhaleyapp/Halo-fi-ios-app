//
//  SubscriptionViewModel.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/18/25.
//

import Observation
import UIKit

enum PurchaseResult {
  case success
  case pending
  case productsNotReady
  case cancelled
  case failure(String)
}

enum RestoreResult {
  case restored
  case noneFound
  case failure(String)
}

@MainActor
@Observable
class SubscriptionViewModel {
  // Inputs / dependencies
  private let subscriptionService: SubscriptionService
  
  // State that impacts UI
  var selectedPlan: SubscriptionPlan = .pro
  var billingCycle: BillingCycle = .monthly
  var isLoadingPurchase = false
  
  // Alert messages (view can bind to bools, VM sets messages)
  var purchaseAlertMessage = ""
  var restoreAlertMessage = ""
  
  init(subscriptionService: SubscriptionService) {
    self.subscriptionService = subscriptionService
    updateSelectedPlanFromSubscription()
  }
  
  var currentPlanName: String {
    subscriptionService.currentSubscription.displayName
  }
  
  var renewalDate: Date? {
    subscriptionService.renewalDate
  }
  
  var hasActiveSubscription: Bool {
    subscriptionService.hasActiveSubscription
  }
  
  var isServiceLoading: Bool {
    subscriptionService.isLoading
  }
  
  func onAppear() async {
#if DEBUG
    // Skip heavy work in SwiftUI previews
    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
      return
    }
#endif
    
    if subscriptionService.availablePackages.isEmpty && !subscriptionService.isLoading {
      await subscriptionService.initialize()
    }
    updateSelectedPlanFromSubscription()
  }
  
  func updateSelectedPlanFromSubscription() {
    switch subscriptionService.currentSubscription {
    case .basic: selectedPlan = .basic
    case .pro:   selectedPlan = .pro
    case .max:   selectedPlan = .max
    default:     break
    }
  }
  
  func handlePurchase() async -> PurchaseResult {
    // Check if products are loaded
    if subscriptionService.availablePackages.isEmpty {
      if !subscriptionService.isLoading {
        await subscriptionService.initialize()
      }
      
      if subscriptionService.isLoading {
        var waitCount = 0
        while subscriptionService.isLoading && waitCount < 10 {
          try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
          waitCount += 1
        }
      }
      
      if subscriptionService.availablePackages.isEmpty {
        purchaseAlertMessage = "Products are still loading. Please wait a moment and try again."
        return .productsNotReady
      }
    }
    
    isLoadingPurchase = true
    let productId = selectedPlan.productId(for: billingCycle)
    
    do {
      let result = try await subscriptionService.purchase(productId: productId)
      isLoadingPurchase = false
      
      if result.success {
        purchaseAlertMessage = "Successfully subscribed to \(selectedPlan.displayName)!"
        updateSelectedPlanFromSubscription()
        return .success
      } else {
        purchaseAlertMessage = "Purchase completed but subscription status is pending."
        return .pending
      }
    } catch SubscriptionError.purchaseCancelled {
      isLoadingPurchase = false
      // user cancelled – no alert needed if you don't want one
      return .cancelled
    } catch {
      isLoadingPurchase = false
      purchaseAlertMessage = error.localizedDescription
      return .failure(error.localizedDescription)
    }
  }
  
  func handleRestorePurchases() async -> RestoreResult {
    isLoadingPurchase = true
    
    do {
      try await subscriptionService.restorePurchases()
      isLoadingPurchase = false
      updateSelectedPlanFromSubscription()
      
      if subscriptionService.hasActiveSubscription {
        restoreAlertMessage = "Purchases restored successfully! You have access to \(subscriptionService.currentSubscription.displayName)."
        return .restored
      } else {
        restoreAlertMessage = "No active purchases found to restore."
        return .noneFound
      }
    } catch {
      isLoadingPurchase = false
      restoreAlertMessage = error.localizedDescription
      return .failure(error.localizedDescription)
    }
  }
  
  func handleCancelSubscription() {
    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
      UIApplication.shared.open(url)
    }
  }
}
