//
//  UnifiedOnboardingFlowView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/10/25.
//
//  Unified onboarding flow that guides users through:
//  1. Sign Up - Create account
//  2. Subscription - Choose a plan
//  3. Plaid - Connect bank accounts
//
//  ## Design Principles
//  - View handles layout and wiring; coordinator handles state and logic
//  - Bootstrapping (initial step selection) is separate from user navigation
//  - Async operations cannot override user-initiated navigation
//  - Users can exit onboarding at any time via close button
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
  
  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 0) {
          // Step indicator (hidden on sign up step)
          if coordinator.currentStep != .signUp {
            AccessibleOnboardingHeader(currentStep: coordinator.currentStep)
          }

          // Step content with transitions
          stepContent
            .id(coordinator.currentStep)
        }
        .animation(.easeInOut(duration: 0.3), value: coordinator.currentStep)

        // Close button overlay (shown after sign up)
        if coordinator.currentStep != .signUp {
          closeButtonOverlay
        }
      }
      .navigationBarHidden(true)
    }
    .alert("Error", isPresented: $showingError) {
      Button("OK") { }
    } message: {
      Text(errorMessage)
    }
    .task {
      await bootstrapOnboarding()
    }
    .onChange(of: userManager.isAuthenticated) { _, isAuthenticated in
      handleAuthenticationChange(isAuthenticated: isAuthenticated)
    }
  }
  
  // MARK: - Step Content
  
  @ViewBuilder
  private var stepContent: some View {
    switch coordinator.currentStep {
    case .signUp:
      SignUpOnboardingStep(
        coordinator: coordinator,
        onComplete: handleSignUpComplete
      )
      .viewTransition(.fade)

    case .subscription:
      SubscriptionOnboardingStep(
        coordinator: coordinator,
        onComplete: handleSubscriptionComplete,
        onBack: backActionForSubscription
      )
      .viewTransition(.slideForward)

    case .plaid:
      PlaidOnboardingStep(
        coordinator: coordinator,
        onComplete: handlePlaidComplete,
        onBack: { coordinator.previousStep() }
      )
      .viewTransition(.slideForward)
    }
  }
  
  // MARK: - Close Button
  
  private var closeButtonOverlay: some View {
    VStack {
      HStack {
        Spacer()
        CloseOnboardingButton(onClose: handleCloseOnboarding)
          .padding(.trailing, 16)
          .padding(.top, 8)
      }
      Spacer()
    }
  }
  
  // MARK: - Bootstrapping
  
  /// Determines the starting step and initializes subscription service.
  ///
  /// This runs once on appear. The flow:
  /// 1. Initialize subscription service (async)
  /// 2. Determine starting step based on auth/subscription state
  /// 3. Mark bootstrapping as complete
  ///
  /// After bootstrapping, async results cannot override user navigation.
  private func bootstrapOnboarding() async {
    // Initialize subscription service to get accurate subscription status
    await subscriptionService.initialize()
    
    // Determine starting step on main actor
    await MainActor.run {
      // Only apply if user hasn't already started navigating
      guard coordinator.isBootstrapping && !coordinator.hasUserInteracted else {
        coordinator.finishBootstrapping()
        return
      }
      
      let startingStep = coordinator.determineStartingStep(
        isAuthenticated: userManager.isAuthenticated,
        hasActiveSubscription: subscriptionService.hasActiveSubscription
      )
      
      // Set the step (this won't trigger didSet since we're still bootstrapping)
      coordinator.setStepIfBootstrapping(startingStep)
      coordinator.finishBootstrapping()
    }
  }
  
  // MARK: - Step Handlers
  
  private func handleSignUpComplete() {
    coordinator.markStepCompleted(.signUp)
    // Always go to subscription after signup
    // Don't check subscription status - RevenueCat might have stale cache for new users
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
  
  /// Back action for subscription step.
  /// Returns nil if signup was already completed (can't go back to signup).
  private var backActionForSubscription: (() -> Void)? {
    coordinator.signUpCompleted ? nil : { coordinator.previousStep() }
  }
  
  // MARK: - Close / Exit
  
  private func handleCloseOnboarding() {
    userManager.completeOnboarding()
  }
  
  // MARK: - Auth State Changes
  
  private func handleAuthenticationChange(isAuthenticated: Bool) {
    if !isAuthenticated {
      // User signed out - clear state and dismiss
      coordinator.reset()
      dismiss()
    }
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

struct AccessibleOnboardingHeader: View {
  let currentStep: OnboardingStep
  
  private var stepIndex: Int {
    OnboardingStep.allCases.firstIndex(of: currentStep) ?? 0
  }
  
  private var totalSteps: Int {
    OnboardingStep.allCases.count
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Step \(stepIndex + 1) of \(totalSteps)")
        .font(.title2.weight(.semibold))   // nice and big
        .foregroundColor(.white)
      
      Text(currentStep.title)              // “Create your account”, “Choose a plan”, etc.
        .font(.title.weight(.bold))
        .foregroundColor(.white)
        .accessibilityAddTraits(.isHeader)
      
      ProgressView(
        value: Double(stepIndex + 1),
        total: Double(totalSteps)
      )
      .progressViewStyle(.linear)
      .tint(.blue)
      .accessibilityHidden(true) // just visual; VoiceOver gets a single combined label
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(Color.black)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Step \(stepIndex + 1) of \(totalSteps): \(currentStep.title)")
  }
}

// MARK: - Preview

#Preview {
  UnifiedOnboardingFlowView()
    .environment(UserManager())
    .environment(SubscriptionService())
    .environment(BankDataManager())
}
