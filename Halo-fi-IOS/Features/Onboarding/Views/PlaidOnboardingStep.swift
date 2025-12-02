//
//  PlaidOnboardingStep.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/1/25.
//

import SwiftUI

struct PlaidOnboardingStep: View {
  let coordinator: OnboardingCoordinator
  @Environment(BankDataManager.self) private var bankDataManager
  @Environment(UserManager.self) private var userManager
  let onComplete: () -> Void
  let onBack: () -> Void
  
  @State private var hasCheckedAccounts = false
  
  var body: some View {
    PlaidOnboardingView(onComplete: onComplete, onBack: onBack)
      .onAppear {
        // Check if user already has connected accounts - use accounts as source of truth
        if !hasCheckedAccounts {
          hasCheckedAccounts = true
          Task {
            // Fetch accounts to check if user already has connected banks
            do {
              try await bankDataManager.fetchAccounts(forceRefresh: false)
              
              await MainActor.run {
                // If user already has accounts, treat Plaid step as complete
                let hasAccounts = bankDataManager.accounts?.isEmpty == false
                
                if hasAccounts {
                  // Mark Plaid step as completed
                  coordinator.markStepCompleted(.plaid)
                  // Complete onboarding
                  userManager.completeOnboarding()
                  // Auto-advance after a brief delay
                  Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    await MainActor.run {
                      onComplete()
                    }
                  }
                }
              }
            } catch {
              // If we can't fetch accounts, continue with normal Plaid flow
              // This handles cases where network is unavailable or user hasn't connected yet
            }
          }
        }
      }
  }
}
