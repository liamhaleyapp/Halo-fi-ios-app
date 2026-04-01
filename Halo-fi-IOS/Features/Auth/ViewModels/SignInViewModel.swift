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
  private var isPhoneValid: Bool {
    if case .valid = USPhoneFormatting.validate(phoneNumber) {
      return true
    }
    return false
  }
  
  private var isPasswordValid: Bool {
    !password.isEmpty
  }
  
  // Per-field errors
  var phoneError: String? {
    guard hasAttemptedSubmit else { return nil }
    let result = USPhoneFormatting.validate(phoneNumber)
    return USPhoneFormatting.errorMessage(for: result)
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

  func socialSignIn(
    provider: String,
    idToken: String,
    nonce: String? = nil,
    using userManager: UserManager,
    subscriptionService: SubscriptionService,
    onNeedsSubscription: @escaping () -> Void,
    onNeedsPlaid: @escaping () -> Void,
    onSignedInAndOnboarded: @escaping () -> Void
  ) async {
    isLoading = true
    defer { isLoading = false }

    do {
      try await userManager.socialSignIn(provider: provider, idToken: idToken, nonce: nonce)

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
        ? "Unable to sign in with \(provider). Please try again."
        : error.localizedDescription
      showingError = true
    }
  }

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
      guard let fullPhone = USPhoneFormatting.formatForAPI(phoneNumber) else {
        errorMessage = "Invalid phone number format."
        showingError = true
        return
      }
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
