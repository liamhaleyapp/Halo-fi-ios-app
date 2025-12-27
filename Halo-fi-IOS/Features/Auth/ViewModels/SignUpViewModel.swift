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
  
  // MARK: - UI state
  
  var isLoading = false
  var errorMessage = ""
  var showingError = false
  var hasAttemptedSubmit = false
  
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
    isFirstNameValid &&
    isEmailValid &&
    isPhoneValid &&
    isPasswordValid &&
    isConfirmPasswordValid &&
    isDateOfBirthValid
  }
  
  // MARK: - Actions
  
  func createAccount(using userManager: UserManager, onComplete: (() -> Void)?) async {
    
    hasAttemptedSubmit = true
    
    guard isFormValid else {
      return
    }
    
    isLoading = true
    defer { isLoading = false }

    do {
      guard let fullPhone = USPhoneFormatting.formatForAPI(phoneNumber) else {
        errorMessage = "Invalid phone number format."
        showingError = true
        return
      }

      try await userManager.signUp(
        firstName: trimmedFirstName,
        lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
        phone: fullPhone,
        email: trimmedEmail,
        password: password,
        dateOfBirth: dateOfBirth
      )
      
      try await userManager.signIn(
        phoneNumber: fullPhone,
        password: password
      )
      
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
}
