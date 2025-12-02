//
//  OnboardingPersistence.swift
//  Halo-fi-IOS
//
//  Centralized persistence helper for onboarding state.
//  Wraps UserDefaults access to avoid scattered keys and provide type-safe access.
//

import Foundation

/// Handles all UserDefaults persistence for onboarding state.
/// Using a dedicated helper ensures:
/// - Keys are defined in one place
/// - Persistence logic is testable
/// - Detection of "has persisted state" is reliable (uses `object(forKey:)` not `integer(forKey:)`)
struct OnboardingPersistence {
  
  // MARK: - Keys
  
  private enum Keys {
    static let currentStep = "onboarding_current_step"
    static let signUpCompleted = "onboarding_signup_completed"
    static let subscriptionCompleted = "onboarding_subscription_completed"
  }
  
  private let defaults: UserDefaults
  
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }
  
  // MARK: - Current Step
  
  /// The saved onboarding step, if any.
  /// Returns `nil` if no step has been persisted (user never started onboarding).
  /// This correctly handles the case where `signUp` (rawValue 0) was persisted.
  var savedStep: OnboardingStep? {
    // Use object(forKey:) to detect if a value was ever saved.
    // integer(forKey:) returns 0 for missing keys, which conflicts with .signUp's rawValue.
    guard defaults.object(forKey: Keys.currentStep) != nil else {
      return nil
    }
    let rawValue = defaults.integer(forKey: Keys.currentStep)
    return OnboardingStep(rawValue: rawValue)
  }
  
  /// Whether any onboarding state has been persisted.
  var hasPersistedState: Bool {
    savedStep != nil
  }
  
  func saveStep(_ step: OnboardingStep) {
    defaults.set(step.rawValue, forKey: Keys.currentStep)
  }
  
  // MARK: - Step Completion
  
  var signUpCompleted: Bool {
    get { defaults.bool(forKey: Keys.signUpCompleted) }
    nonmutating set { defaults.set(newValue, forKey: Keys.signUpCompleted) }
  }
  
  var subscriptionCompleted: Bool {
    get { defaults.bool(forKey: Keys.subscriptionCompleted) }
    nonmutating set { defaults.set(newValue, forKey: Keys.subscriptionCompleted) }
  }
  
  // MARK: - Clear
  
  /// Removes all persisted onboarding state.
  /// Called when onboarding completes successfully or user signs out.
  func clearAll() {
    defaults.removeObject(forKey: Keys.currentStep)
    defaults.removeObject(forKey: Keys.signUpCompleted)
    defaults.removeObject(forKey: Keys.subscriptionCompleted)
  }
}

