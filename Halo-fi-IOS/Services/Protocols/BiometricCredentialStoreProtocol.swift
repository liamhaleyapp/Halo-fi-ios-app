//
//  BiometricCredentialStoreProtocol.swift
//  Halo-fi-IOS
//
//  Protocol for biometric-protected credential storage. Reads trigger the
//  Face ID / Touch ID prompt via SecAccessControl on the Keychain item.
//

import Foundation

struct BiometricCredentials: Equatable {
  let email: String
  let password: String
}

protocol BiometricCredentialStoreProtocol {
  /// Existence check that does NOT trigger a biometry prompt.
  var hasEnrolledCredentials: Bool { get }

  /// Persists credentials behind biometric ACL.
  /// Caller should run BiometricAuthService.authenticate(...) first to confirm
  /// user intent — this call only performs the Keychain write.
  func save(_ credentials: BiometricCredentials) throws

  /// Reads credentials. The Keychain access itself triggers the system Face ID /
  /// Touch ID prompt with the supplied reason string.
  func read(reason: String) async throws -> BiometricCredentials

  /// Wipes the stored credentials. Called on sign-out, password change, or
  /// when the ACL has been invalidated by a biometric re-enrollment.
  func clear()
}

enum BiometricCredentialError: Error, Equatable {
  case userCancelled
  case biometricsInvalidated
  case notFound
  case notAvailable
  case keychainError(OSStatus)
  case encodingError
}
