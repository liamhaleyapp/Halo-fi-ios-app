//
//  SubscriptionOnboardingStep.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/1/25.
//

import SwiftUI

struct SubscriptionOnboardingStep: View {
  let coordinator: OnboardingCoordinator
  @Environment(SubscriptionService.self) private var subscriptionService
  let onComplete: () -> Void
  let onBack: (() -> Void)?
  
  @State private var hasCheckedSubscription = false
  
  var body: some View {
    SubscriptionOnboardingFlowView(
      onComplete: onComplete,
      hideBackButton: onBack == nil
    )
    .onAppear {
      // Check subscription status on appear - use entitlements as source of truth
      if !hasCheckedSubscription {
        hasCheckedSubscription = true
        Task {
          // Ensure subscription service is initialized
          if subscriptionService.availablePackages.isEmpty {
            await subscriptionService.initialize()
          } else {
            // Refresh subscription status to get latest from RevenueCat
            await subscriptionService.checkSubscriptionStatus()
          }
          
          await MainActor.run {
            // If user already has active subscription, treat step as complete
            // This handles cases like:
            // - User subscribed on another device
            // - User restored purchases
            // - User has existing subscription from previous account
            if subscriptionService.hasActiveSubscription {
              // Mark subscription step as completed
              coordinator.markStepCompleted(.subscription)
              // Auto-advance after a brief delay to show the subscription view
              Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await MainActor.run {
                  onComplete()
                }
              }
            }
          }
        }
      }
    }
    .onChange(of: subscriptionService.hasActiveSubscription) { oldValue, newValue in
      // Also handle subscription becoming active after user subscribes
      if newValue && !oldValue {
        // Small delay to ensure subscription status is fully updated
        Task {
          try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
          await MainActor.run {
            coordinator.markStepCompleted(.subscription)
            onComplete()
          }
        }
      }
    }
  }
}
