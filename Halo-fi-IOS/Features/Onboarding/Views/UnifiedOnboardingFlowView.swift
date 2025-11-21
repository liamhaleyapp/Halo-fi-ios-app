//
//  UnifiedOnboardingFlowView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/10/25.
//

import SwiftUI

struct UnifiedOnboardingFlowView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager
  @Environment(SubscriptionService.self) private var subscriptionService
  @Environment(BankDataManager.self) private var bankDataManager
  
  @State private var coordinator = OnboardingCoordinator()
  @State private var showingError = false
  @State private var errorMessage = ""
  @State private var hasDeterminedInitialStep = false
  
  var body: some View {
    NavigationView {
      ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 0) {
          // Step Indicator
          if coordinator.currentStep != .signUp {
            OnboardingStepIndicator(
              currentStep: coordinator.currentStep,
              signUpCompleted: coordinator.signUpCompleted,
              subscriptionCompleted: coordinator.subscriptionCompleted
            )
            .background(Color.black)
          }
          
          // Content based on current step
          Group {
            switch coordinator.currentStep {
            case .signUp:
              SignUpOnboardingStep(
                coordinator: coordinator,
                onComplete: {
                  handleSignUpComplete()
                }
              )
              
            case .subscription:
              SubscriptionOnboardingStep(
                coordinator: coordinator,
                onComplete: {
                  handleSubscriptionComplete()
                },
                onBack: coordinator.signUpCompleted ? nil : {
                  coordinator.previousStep()
                }
              )
              
            case .plaid:
              PlaidOnboardingStep(
                coordinator: coordinator,
                onComplete: {
                  handlePlaidComplete()
                },
                onBack: {
                  coordinator.previousStep()
                }
              )
            }
          }
        }
      }
      .navigationBarHidden(true)
    }
    .alert("Error", isPresented: $showingError) {
      Button("OK") { }
    } message: {
      Text(errorMessage)
    }
    .onAppear {
      // Only determine starting step once, unless we're coming back from signup
      if !hasDeterminedInitialStep {
        determineStartingStep()
        hasDeterminedInitialStep = true
      }
    }
    .onChange(of: userManager.isAuthenticated) { oldValue, newValue in
      // If user signs out, dismiss the onboarding flow
      // MainTabView will show the sign in screen
      if !newValue {
        coordinator.clearPersistedState()
        dismiss()
      }
    }
  }
  
  private func determineStartingStep() {
    // Check if user is already signed up
    if userManager.isAuthenticated {
      // Mark signup as completed if not already marked
      if !coordinator.signUpCompleted {
        coordinator.markStepCompleted(.signUp)
      }
      
      // Check if we have persisted state (user was in middle of onboarding)
      let savedStepRaw = UserDefaults.standard.integer(forKey: "onboarding_current_step")
      let hasPersistedState = savedStepRaw != 0
      
      // If no persisted state, user just signed up - ALWAYS go to subscription step
      // Don't check subscription status for new signups to avoid RevenueCat cache issues
      if !hasPersistedState {
        coordinator.goToStep(.subscription)
        return
      }
      
      // User has persisted state - they were in middle of onboarding
      // Check subscription status to determine where to resume
      Task {
        await subscriptionService.initialize()
        await MainActor.run {
          // If user hasn't completed subscription step, always go to subscription
          // This ensures users go through subscription step even if RevenueCat has stale cache
          if !coordinator.subscriptionCompleted {
            coordinator.goToStep(.subscription)
            return
          }
          
          // User has completed subscription step - check if they have active subscription
          // Only trust subscription status if they've actually completed the subscription step
          if subscriptionService.hasActiveSubscription {
            // User has subscription - go to Plaid
            if coordinator.currentStep != .plaid {
              coordinator.goToStep(.plaid)
            }
          } else {
            // No subscription - but they completed subscription step, so they might be on Plaid
            // If they're on Plaid without subscription, go back to subscription
            if coordinator.currentStep == .plaid {
              coordinator.goToStep(.subscription)
            }
            // Otherwise, stay on current step
          }
        }
      }
    } else {
      // Not authenticated - start at signup
      // Clear any persisted state since user isn't authenticated
      coordinator.clearPersistedState()
      coordinator.goToStep(.signUp)
    }
  }
  
  private func handleSignUpComplete() {
    coordinator.markStepCompleted(.signUp)
    // Always go to subscription step after signup, regardless of subscription status
    // New users need to select a subscription plan
    coordinator.goToStep(.subscription)
  }
  
  private func handleSubscriptionComplete() {
    coordinator.markStepCompleted(.subscription)
    coordinator.nextStep()
  }
  
  private func handlePlaidComplete() {
    coordinator.markStepCompleted(.plaid)
    userManager.completeOnboarding()
    dismiss()
  }
}

// MARK: - Sign Up Step
struct SignUpOnboardingStep: View {
  let coordinator: OnboardingCoordinator
  let onComplete: () -> Void
  
  var body: some View {
    SignUpView(onComplete: onComplete)
  }
}

// MARK: - Subscription Step
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

// MARK: - Plaid Step
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

#Preview {
  UnifiedOnboardingFlowView()
    .environment(UserManager())
    .environment(SubscriptionService())
    .environment(BankDataManager())
}

