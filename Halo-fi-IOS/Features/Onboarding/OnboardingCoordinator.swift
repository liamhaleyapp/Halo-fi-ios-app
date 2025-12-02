//
//  OnboardingCoordinator.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/10/25.
//

import SwiftUI

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
  case signUp = 0
  case subscription = 1
  case plaid = 2
  
  var title: String {
    switch self {
    case .signUp:
      return "Create Account"
    case .subscription:
      return "Choose Plan"
    case .plaid:
      return "Connect Bank"
    }
  }
  
  var description: String {
    switch self {
    case .signUp:
      return "Sign up to get started"
    case .subscription:
      return "Select your subscription"
    case .plaid:
      return "Link your bank account"
    }
  }
}

// MARK: - Onboarding Coordinator

/// Manages onboarding flow state, navigation, and persistence.
///
/// ## Responsibilities
/// - Tracks current step and step completion status
/// - Persists state to UserDefaults (via OnboardingPersistence)
/// - Determines the correct starting step based on auth/subscription/persistence state
/// - Distinguishes between bootstrapping (initial step selection) and user-driven navigation
///
/// ## Bootstrapping vs User Navigation
/// When onboarding starts, we "bootstrap" by selecting the appropriate starting step.
/// Once bootstrapping completes, user navigation (back/next buttons) takes precedence.
/// Late-arriving async results (e.g., subscription status) cannot override user choices.
@Observable
@MainActor
class OnboardingCoordinator {
  
  // MARK: - Persistence
  
  private let persistence: OnboardingPersistence
  
  // MARK: - State
  
  /// The current onboarding step being displayed.
  var currentStep: OnboardingStep {
    didSet {
      persistence.saveStep(currentStep)
    }
  }
  
  /// Whether onboarding has completed (all steps done).
  var isCompleted = false
  
  /// Tracks whether bootstrapping has finished.
  /// During bootstrapping, the coordinator determines the starting step.
  /// After bootstrapping, async results cannot override user navigation.
  private(set) var isBootstrapping = true
  
  /// Set to true once the user has manually navigated (back/next).
  /// This prevents async subscription checks from overriding user choices.
  private(set) var hasUserInteracted = false
  
  // MARK: - Step Completion
  
  var signUpCompleted: Bool {
    didSet {
      persistence.signUpCompleted = signUpCompleted
    }
  }
  
  var subscriptionCompleted: Bool {
    didSet {
      persistence.subscriptionCompleted = subscriptionCompleted
    }
  }
  
  var plaidCompleted = false
  
  // MARK: - Initialization
  
  init(persistence: OnboardingPersistence = OnboardingPersistence()) {
    self.persistence = persistence
    
    // Restore persisted state
    self.currentStep = persistence.savedStep ?? .signUp
    self.signUpCompleted = persistence.signUpCompleted
    self.subscriptionCompleted = persistence.subscriptionCompleted
  }
  
  // MARK: - Starting Step Logic
  
  func determineStartingStep(
    isAuthenticated: Bool,
    hasActiveSubscription: Bool
  ) -> OnboardingStep {
    
    // Not authenticated → always start at sign up
    guard isAuthenticated else {
      return .signUp
    }
    
    // Authenticated: mark signup as complete if not already
    if !signUpCompleted {
      signUpCompleted = true
    }
    
    // No persisted state = user just signed up (fresh onboarding)
    // Always go to subscription step - don't check subscription status yet
    // because RevenueCat cache might have stale data for new users
    guard persistence.hasPersistedState else {
      return .subscription
    }
    
    // Has persisted state = resuming onboarding
    // Use subscription status to validate where to resume
    
    // If subscription step not completed → go to subscription
    // (Even if RevenueCat says they have subscription - they need to complete the step)
    guard subscriptionCompleted else {
      return .subscription
    }
    
    // Subscription step completed - check actual subscription status
    if hasActiveSubscription {
      // Valid subscription → continue to/stay on Plaid
      return .plaid
    } else {
      // No active subscription but completed subscription step
      // This might mean subscription expired or was cancelled
      // Send them back to subscription to renew
      return .subscription
    }
  }
  
  /// Called after bootstrapping logic completes.
  /// After this, async results cannot override user navigation.
  func finishBootstrapping() {
    isBootstrapping = false
  }
  
  /// Attempts to set the step during bootstrapping.
  /// Will be ignored if user has already interacted.
  func setStepIfBootstrapping(_ step: OnboardingStep) {
    guard isBootstrapping && !hasUserInteracted else {
      return
    }
    currentStep = step
  }
  
  // MARK: - Navigation (User-Driven)
  
  func nextStep() {
    hasUserInteracted = true
    guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
      isCompleted = true
      return
    }
    currentStep = next
  }
  
  func previousStep() {
    hasUserInteracted = true
    guard let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
      return
    }
    currentStep = previous
  }
  
  func goToStep(_ step: OnboardingStep) {
    hasUserInteracted = true
    currentStep = step
  }
  
  // MARK: - Step Completion
  
  func markStepCompleted(_ step: OnboardingStep) {
    switch step {
    case .signUp:
      signUpCompleted = true
    case .subscription:
      subscriptionCompleted = true
    case .plaid:
      plaidCompleted = true
      isCompleted = true
      clearPersistedState()
    }
  }
  
  // MARK: - Persistence
  
  func clearPersistedState() {
    persistence.clearAll()
  }
  
  /// Resets the coordinator to initial state.
  /// Called when user signs out to ensure clean slate.
  func reset() {
    clearPersistedState()
    currentStep = .signUp
    signUpCompleted = false
    subscriptionCompleted = false
    plaidCompleted = false
    isCompleted = false
    isBootstrapping = true
    hasUserInteracted = false
  }
  
  // MARK: - Computed Properties
  
  var progress: Double {
    let completedSteps = [signUpCompleted, subscriptionCompleted, plaidCompleted].filter { $0 }.count
    return Double(completedSteps) / Double(OnboardingStep.allCases.count)
  }
  
  var currentStepIndex: Int {
    currentStep.rawValue
  }
  
  var totalSteps: Int {
    OnboardingStep.allCases.count
  }
}
