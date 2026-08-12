//
//  SignInViewModel.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/18/25.
//

import Foundation
import Observation

@MainActor
@Observable
class SignInViewModel {
  // Form state
  var email = ""
  var password = ""

  // UI state
  var isLoading = false
  var errorMessage = ""
  var showingError = false
  var hasAttemptedSubmit = false

  // Biometric enrollment state — driven from the post-sign-in flow.
  // The view binds `showingBiometricEnrollment` to a sheet; choosing
  // Enable / Not Now resolves the pending route via handleEnrollmentChoice.
  var showingBiometricEnrollment = false
  private var pendingCredentialsForEnrollment: BiometricCredentials?
  private var pendingPostSignInAction: (() -> Void)?

  /// One-time UserDefaults flag — once the enrollment sheet has been shown,
  /// we don't pester the user again. They can still enroll via Settings.
  private static let enrollmentOfferedKey = "biometric_enrollment_offered"

  // Helpers
  private var isEmailValid: Bool {
    let trimmed = email.trimmingCharacters(in: .whitespaces)
    // Lightweight format check; the backend performs full validation.
    return trimmed.contains("@") && trimmed.contains(".")
      && !trimmed.hasPrefix("@") && !trimmed.hasSuffix("@")
  }

  private var isPasswordValid: Bool {
    !password.isEmpty
  }

  // Per-field errors
  var emailError: String? {
    guard hasAttemptedSubmit else { return nil }
    if email.trimmingCharacters(in: .whitespaces).isEmpty { return "Email is required." }
    if !isEmailValid { return "Enter a valid email address." }
    return nil
  }

  var passwordError: String? {
    guard hasAttemptedSubmit else { return nil }
    if password.isEmpty { return "Password is required." }
    return nil
  }

  var isFormValid: Bool {
    isEmailValid && isPasswordValid
  }

  // Actions

  func socialSignIn(
    provider: String,
    idToken: String,
    nonce: String? = nil,
    firstName: String? = nil,
    lastName: String? = nil,
    using userManager: UserManager,
    subscriptionService: SubscriptionService,
    onNeedsSubscription: @escaping () -> Void,
    onNeedsPlaid: @escaping () -> Void,
    onSignedInAndOnboarded: @escaping () -> Void
  ) async {
    isLoading = true
    defer { isLoading = false }

    do {
      try await userManager.socialSignIn(
        provider: provider, idToken: idToken, nonce: nonce,
        firstName: firstName, lastName: lastName
      )

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
    biometricAuthService: BiometricAuthService,
    biometricCredentialStore: BiometricCredentialStoreProtocol,
    onNeedsSubscription: @escaping () -> Void,
    onNeedsPlaid: @escaping () -> Void,
    onSignedInAndOnboarded: @escaping () -> Void
  ) async {
    hasAttemptedSubmit = true

    guard isFormValid else { return }

    isLoading = true

    do {
      let loginEmail = email.trimmingCharacters(in: .whitespaces)
      try await userManager.signIn(email: loginEmail, password: password)

      // Successful sign-in. Decide where to route.
      let routeAction = await resolveRouteAction(
        userManager: userManager,
        subscriptionService: subscriptionService,
        onNeedsSubscription: onNeedsSubscription,
        onNeedsPlaid: onNeedsPlaid,
        onSignedInAndOnboarded: onSignedInAndOnboarded
      )

      isLoading = false

      // Offer Face ID enrollment if applicable, otherwise route immediately.
      let creds = BiometricCredentials(email: loginEmail, password: password)
      if shouldOfferEnrollment(
        biometricAuthService: biometricAuthService,
        credentialStore: biometricCredentialStore
      ) {
        pendingCredentialsForEnrollment = creds
        pendingPostSignInAction = routeAction
        showingBiometricEnrollment = true
      } else {
        routeAction()
      }
    } catch {
      isLoading = false
      errorMessage = error.localizedDescription.isEmpty
      ? "Unable to sign in. Please check your credentials and try again."
      : error.localizedDescription
      showingError = true
    }
  }

  /// Auth path triggered when the user taps the phone field on a device with
  /// enrolled biometric credentials. Reads creds from the Keychain (which
  /// triggers the OS Face ID / Touch ID prompt) and calls the sign-in API.
  func biometricSignIn(
    using userManager: UserManager,
    subscriptionService: SubscriptionService,
    credentialStore: BiometricCredentialStoreProtocol,
    onNeedsSubscription: @escaping () -> Void,
    onNeedsPlaid: @escaping () -> Void,
    onSignedInAndOnboarded: @escaping () -> Void,
    onCancelled: @escaping () -> Void = {}
  ) async {
    do {
      let creds = try await credentialStore.read(reason: "Sign in to HaloFi")

      isLoading = true
      defer { isLoading = false }

      try await userManager.signIn(email: creds.email, password: creds.password)

      let routeAction = await resolveRouteAction(
        userManager: userManager,
        subscriptionService: subscriptionService,
        onNeedsSubscription: onNeedsSubscription,
        onNeedsPlaid: onNeedsPlaid,
        onSignedInAndOnboarded: onSignedInAndOnboarded
      )
      routeAction()
    } catch BiometricCredentialError.userCancelled {
      onCancelled()
    } catch BiometricCredentialError.notFound {
      // No enrolled creds — caller shouldn't have invoked us, but handle it.
      onCancelled()
    } catch BiometricCredentialError.biometricsInvalidated {
      // Face ID was re-enrolled on the device — the OS invalidated the ACL.
      // Wipe stored creds so the user re-enrolls after a manual sign-in.
      credentialStore.clear()
      // Reset the once-asked flag so the post-sign-in enrollment sheet
      // returns automatically next time. Visually-impaired users in
      // particular benefit from not having to hunt for Settings to
      // re-enable a feature that broke through no fault of their own.
      UserDefaults.standard.removeObject(forKey: Self.enrollmentOfferedKey)
      errorMessage = "Face ID changed on this device. Please sign in manually to re-enable Face ID."
      showingError = true
    } catch {
      // 401 (password rotated server-side) or other failure — drop the
      // stored creds and let the user enter manually. Re-prompt for
      // enrollment after they sign in successfully again.
      credentialStore.clear()
      UserDefaults.standard.removeObject(forKey: Self.enrollmentOfferedKey)
      isLoading = false
      errorMessage = "Couldn't sign in with Face ID. Please enter your credentials."
      showingError = true
    }
  }

  /// Handles the user's choice from the post-sign-in enrollment sheet.
  /// Persists the offered flag (so we don't ask again), saves credentials if
  /// the user enabled, then fires the deferred routing action.
  func handleEnrollmentChoice(
    enable: Bool,
    biometricAuthService: BiometricAuthService,
    credentialStore: BiometricCredentialStoreProtocol
  ) async {
    UserDefaults.standard.set(true, forKey: Self.enrollmentOfferedKey)

    if enable, let creds = pendingCredentialsForEnrollment {
      do {
        try await biometricAuthService.authenticate(reason: "Enable Face ID sign-in")
        try credentialStore.save(creds)
      } catch {
        // User cancelled / failed — proceed to route without enrollment.
        Logger.info("Biometric enrollment skipped: \(error.localizedDescription)")
      }
    }

    pendingCredentialsForEnrollment = nil
    showingBiometricEnrollment = false

    let action = pendingPostSignInAction
    pendingPostSignInAction = nil
    action?()
  }

  // MARK: - Private helpers

  private func resolveRouteAction(
    userManager: UserManager,
    subscriptionService: SubscriptionService,
    onNeedsSubscription: @escaping () -> Void,
    onNeedsPlaid: @escaping () -> Void,
    onSignedInAndOnboarded: @escaping () -> Void
  ) async -> () -> Void {
    if userManager.isOnboarded {
      return onSignedInAndOnboarded
    }

    await subscriptionService.initialize()

    if subscriptionService.hasActiveSubscription {
      return onNeedsPlaid
    } else {
      return onNeedsSubscription
    }
  }

  private func shouldOfferEnrollment(
    biometricAuthService: BiometricAuthService,
    credentialStore: BiometricCredentialStoreProtocol
  ) -> Bool {
    guard !credentialStore.hasEnrolledCredentials else { return false }
    guard !UserDefaults.standard.bool(forKey: Self.enrollmentOfferedKey) else { return false }
    if case .available = biometricAuthService.currentStatus() {
      return true
    }
    return false
  }
}
