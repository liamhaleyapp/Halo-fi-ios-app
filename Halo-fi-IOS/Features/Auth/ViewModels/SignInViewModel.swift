//
//  SignInViewModel.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/18/25.
//

import Observation

@MainActor
@Observable
class SignInViewModel {
  // Form state
  var phoneNumber = ""
  var password = ""
  
  // UI state
  var isLoading = false
  var errorMessage = ""
  var showingError = false
  var hasAttemptedSubmit = false
  
  // Helpers
  private var normalizedPhoneDigits: String {
    phoneNumber.filter { $0.isNumber }
  }
  
  private var isPhoneValid: Bool {
    normalizedPhoneDigits.count >= 10
  }
  
  private var isPasswordValid: Bool {
    !password.isEmpty
  }
  
  // Per-field errors
  var phoneError: String? {
    guard hasAttemptedSubmit else { return nil }
    if normalizedPhoneDigits.isEmpty { return "Phone number is required." }
    if !isPhoneValid { return "Enter a valid phone number (10 digits)." }
    return nil
  }
  
  var passwordError: String? {
    guard hasAttemptedSubmit else { return nil }
    if password.isEmpty { return "Password is required." }
    return nil
  }
  
  var isFormValid: Bool {
    isPhoneValid && isPasswordValid
  }
  
  // Actions
  func signIn(
    using userManager: UserManager,
    subscriptionService: SubscriptionService,
    onNeedsSubscription: @escaping () -> Void,
    onNeedsPlaid: @escaping () -> Void,
    onSignedInAndOnboarded: @escaping () -> Void
  ) async {
    hasAttemptedSubmit = true
    
    guard isFormValid else { return }
    
    isLoading = true
    defer { isLoading = false }
    
    do {
      let fullPhone = "+1" + normalizedPhoneDigits
      try await userManager.signIn(phoneNumber: fullPhone, password: password)
      
      // Decide onboarding outcome
      if userManager.isOnboarded {
        onSignedInAndOnboarded()
        return
      }
      
      await subscriptionService.initialize()
      
      if subscriptionService.hasActiveSubscription {
        onNeedsPlaid()
      } else {
        onNeedsSubscription()
      }
    } catch {
      errorMessage = error.localizedDescription.isEmpty
      ? "Unable to sign in. Please check your credentials and try again."
      : error.localizedDescription
      showingError = true
    }
  }
}
