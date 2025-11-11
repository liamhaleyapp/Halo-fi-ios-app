//
//  OnboardingCoordinator.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/10/25.
//

import SwiftUI

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

/// Manages onboarding flow state and persistence.
/// 
/// This coordinator persists the current onboarding step and completion status
/// to UserDefaults, allowing users to resume where they left off if they close
/// the app mid-onboarding. The persisted state is validated against actual user
/// state (authentication, subscription status) when the app reopens to handle
/// edge cases where the app state might have changed.
@Observable
@MainActor
class OnboardingCoordinator {
  private let stepKey = "onboarding_current_step"
  private let signUpCompletedKey = "onboarding_signup_completed"
  private let subscriptionCompletedKey = "onboarding_subscription_completed"
  
  var currentStep: OnboardingStep {
    didSet {
      saveCurrentStep()
    }
  }
  
  var isCompleted = false
  
  // Track completion status for each step
  var signUpCompleted: Bool {
    didSet {
      UserDefaults.standard.set(signUpCompleted, forKey: signUpCompletedKey)
    }
  }
  
  var subscriptionCompleted: Bool {
    didSet {
      UserDefaults.standard.set(subscriptionCompleted, forKey: subscriptionCompletedKey)
    }
  }
  
  var plaidCompleted = false
  
  init() {
    // Restore persisted state
    let savedStepRaw = UserDefaults.standard.integer(forKey: stepKey)
    if let savedStep = OnboardingStep(rawValue: savedStepRaw) {
      self.currentStep = savedStep
    } else {
      self.currentStep = .signUp
    }
    
    self.signUpCompleted = UserDefaults.standard.bool(forKey: signUpCompletedKey)
    self.subscriptionCompleted = UserDefaults.standard.bool(forKey: subscriptionCompletedKey)
  }
  
  private func saveCurrentStep() {
    UserDefaults.standard.set(currentStep.rawValue, forKey: stepKey)
  }
  
  func clearPersistedState() {
    UserDefaults.standard.removeObject(forKey: stepKey)
    UserDefaults.standard.removeObject(forKey: signUpCompletedKey)
    UserDefaults.standard.removeObject(forKey: subscriptionCompletedKey)
  }
  
  func nextStep() {
    guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
      // All steps completed
      isCompleted = true
      return
    }
    currentStep = nextStep
  }
  
  func previousStep() {
    guard let previousStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
      return
    }
    currentStep = previousStep
  }
  
  func goToStep(_ step: OnboardingStep) {
    currentStep = step
  }
  
  func markStepCompleted(_ step: OnboardingStep) {
    switch step {
    case .signUp:
      signUpCompleted = true
    case .subscription:
      subscriptionCompleted = true
    case .plaid:
      plaidCompleted = true
      isCompleted = true
      // Clear persisted state when onboarding is complete
      clearPersistedState()
    }
  }
  
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

