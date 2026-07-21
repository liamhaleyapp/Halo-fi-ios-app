//
//  SignUpViewModel.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/18/25.
//

import Foundation
import Observation

@MainActor
@Observable
class SignUpViewModel {
  
  // MARK: - Form state
  
  var firstName = ""
  var lastName = ""
  var phoneNumber = ""
  var email = ""
  var password = ""
  var confirmPassword = ""
  var dateOfBirth = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
  /// Optional referral code entered by the invitee. Sent to
  /// /referrals/redeem after the user is signed in. Phase 1 ships
  /// attribution only — discount delivery comes in Phase 2.
  var referralCode = ""
  
  // MARK: - UI state

  var isLoading = false
  var errorMessage = ""
  var showingError = false
  var hasAttemptedSubmit = false

  /// When non-nil, the signup network call has succeeded and the user
  /// must verify the SMS OTP before we sign them in. SignUpView watches
  /// this and pushes PhoneVerificationView. Cleared once verification
  /// completes (success or user cancels).
  ///
  /// We hold the password here only because we need it to perform the
  /// post-verification sign-in — it never leaves memory and is dropped
  /// the instant verification finishes.
  var pendingPhoneVerification: PendingPhoneVerification?

  struct PendingPhoneVerification: Identifiable, Equatable {
    let id = UUID()
    let idUser: String
    let email: String
    let phone: String
    let password: String
    let smsAlreadySent: Bool
  }
  
  // MARK: - Derived / helpers
  
  private var trimmedFirstName: String {
    firstName.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  private var trimmedEmail: String {
    email.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  
  var dateOfBirthRange: ClosedRange<Date> {
    let calendar = Calendar.current
    let minDate = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
    let maxDate = Date()
    return minDate...maxDate
  }
  
  var isDateOfBirthValid: Bool {
    dateOfBirth <= Date()
  }
  
  private var isFirstNameValid: Bool {
    !trimmedFirstName.isEmpty
  }
  
  private var isEmailValid: Bool {
    guard !trimmedEmail.isEmpty else { return false }
    
    // Simple but practical email regex
    let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
    let predicate = NSPredicate(format: "SELF MATCHES[c] %@", pattern)
    return predicate.evaluate(with: trimmedEmail)
  }
  
  private var isPhoneValid: Bool {
    if case .valid = USPhoneFormatting.validate(phoneNumber) {
      return true
    }
    return false
  }
  
  private var isPasswordValid: Bool {
    isStrongPassword(password)
  }
  
  private var isConfirmPasswordValid: Bool {
    !confirmPassword.isEmpty && password == confirmPassword
  }
  
  /// Strong-ish password: 8+ chars, at least one upper, one lower, one digit, one symbol.
  private func isStrongPassword(_ value: String) -> Bool {
    guard value.count >= 8 else { return false }
    
    let hasUpper = value.contains(where: { $0.isUppercase })
    let hasLower = value.contains(where: { $0.isLowercase })
    let hasDigit = value.contains(where: { $0.isNumber })
    let hasSymbol = value.contains(where: { !$0.isNumber && !$0.isLetter && !$0.isWhitespace })
    
    return hasUpper && hasLower && hasDigit && hasSymbol
  }
  
  // MARK: - Per-field error messages
  
  var firstNameError: String? {
    guard hasAttemptedSubmit else { return nil }
    if trimmedFirstName.isEmpty {
      return "First name is required."
    }
    return nil
  }
  
  var emailError: String? {
    guard hasAttemptedSubmit else { return nil }
    if trimmedEmail.isEmpty {
      return "Email is required."
    }
    if !isEmailValid {
      return "Enter a valid email address."
    }
    return nil
  }
  
  var phoneError: String? {
    guard hasAttemptedSubmit else { return nil }
    // Phone is optional — no error when left blank.
    if phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
    let result = USPhoneFormatting.validate(phoneNumber)
    return USPhoneFormatting.errorMessage(for: result)
  }
  
  var passwordError: String? {
    guard hasAttemptedSubmit else { return nil }
    if password.isEmpty {
      return "Password is required."
    }
    if !isPasswordValid {
      return "Password must be 8+ characters and include upper, lower, number, and symbol."
    }
    return nil
  }
  
  var confirmPasswordError: String? {
    guard hasAttemptedSubmit else { return nil }
    if confirmPassword.isEmpty {
      return "Please confirm your password."
    }
    if password != confirmPassword {
      return "Passwords do not match."
    }
    return nil
  }
  
  var dateOfBirthError: String? {
    guard hasAttemptedSubmit else { return nil }
    if !isDateOfBirthValid {
      return "Enter a valid date of birth."
    }
    return nil
  }
  
  // MARK: - Overall form validity
  
  var isFormValid: Bool {
    // Phone and DOB are optional. A phone, if entered, is validated in the
    // register flow; leaving it blank is allowed.
    isFirstNameValid &&
    isEmailValid &&
    isPasswordValid &&
    isConfirmPasswordValid
  }
  
  // MARK: - Actions

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
        ? "Unable to sign up with \(provider). Please try again."
        : error.localizedDescription
      showingError = true
    }
  }

  private struct RedeemBody: Encodable {
    let code: String
  }

  // NetworkService.authenticatedRequest constrains T to Codable, not
  // just Decodable, so we need both directions even though we never
  // re-encode the response.
  private struct RedeemResponse: Codable {
    let success: Bool
    let message: String
  }

  private func redeemReferralIfNeeded() async {
    let trimmed = referralCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    do {
      let body = try JSONEncoder().encode(RedeemBody(code: trimmed.uppercased()))
      let _: RedeemResponse = try await NetworkService.shared.authenticatedRequest(
        endpoint: "/referrals/redeem",
        method: .POST,
        body: body,
        responseType: RedeemResponse.self
      )
    } catch {
      Logger.warning("SignUpViewModel: referral redeem failed (non-blocking) — \(error)")
    }
  }

  func createAccount(using userManager: UserManager, onComplete: (() -> Void)?) async {

    hasAttemptedSubmit = true

    guard isFormValid else {
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      // Phone is optional. If the user entered one, validate + normalize it;
      // if it's blank, sign up without a phone (no SMS verification step).
      var fullPhone = ""
      if !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        guard let normalized = USPhoneFormatting.formatForAPI(phoneNumber) else {
          errorMessage = "Please enter a valid phone number, or leave it blank."
          showingError = true
          return
        }
        fullPhone = normalized
      }

      let signupResponse = try await userManager.signUp(
        firstName: trimmedFirstName,
        lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
        phone: fullPhone,
        email: trimmedEmail,
        password: password
      )

      // If the backend created the user but still needs an SMS OTP to
      // confirm the phone, hand off to PhoneVerificationView. The view
      // calls back into completePhoneVerification(...) on success which
      // performs the sign-in + referral redeem + onComplete chain.
      //
      // Older backends (or future social-only flows) that omit the flag
      // fall through to the original sign-in-immediately path.
      // Only run SMS verification when the user actually provided a phone.
      if signupResponse.requiresPhoneVerification == true && !fullPhone.isEmpty {
        pendingPhoneVerification = PendingPhoneVerification(
          idUser: signupResponse.idUser,
          email: email,
          phone: fullPhone,
          password: password,
          smsAlreadySent: signupResponse.smsSent ?? false
        )
        return
      }

      try await userManager.signIn(
        email: email,
        password: password
      )

      // Best-effort referral redeem. We swallow failures here on
      // purpose — a malformed/unknown code shouldn't block onboarding.
      // Worst case: invitee just isn't attributed; they can ask the
      // inviter for a working code later.
      await redeemReferralIfNeeded()

      onComplete?()
    } catch {
      if let authError = error as? AuthError {
        errorMessage = authError.errorDescription ?? "An error occurred. Please try again."
      } else {
        errorMessage = error.localizedDescription.isEmpty
        ? "An error occurred. Please try again."
        : error.localizedDescription
      }
      showingError = true
    }
  }

  /// Called by SignUpView once the user has successfully entered their
  /// SMS OTP in PhoneVerificationView. Signs the user in with the
  /// password we held in memory during the verification step, redeems
  /// any referral, and fires onComplete.
  func completePhoneVerification(using userManager: UserManager, onComplete: (() -> Void)?) async {
    guard let pending = pendingPhoneVerification else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      try await userManager.signIn(email: pending.email, password: pending.password)
      await redeemReferralIfNeeded()
      pendingPhoneVerification = nil
      onComplete?()
    } catch {
      // Verification succeeded but sign-in failed — leave the
      // verification state cleared and surface a recoverable error.
      // The user can sign in manually from the sign-in screen.
      pendingPhoneVerification = nil
      errorMessage = "Phone verified, but sign-in failed. Please sign in with your phone and password."
      showingError = true
    }
  }
}
