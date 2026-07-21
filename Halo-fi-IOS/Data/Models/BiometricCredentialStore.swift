//
//  BiometricCredentialStore.swift
//  Halo-fi-IOS
//
//  Keychain-backed store for the user's phone + password, gated behind Face ID
//  / Touch ID via SecAccessControl. Used to power the "tap phone field → Face
//  ID → auto-sign-in" fast path.
//
//  V1 stores raw credentials with .biometryCurrentSet; the entry is invalidated
//  by the OS if the user re-enrolls biometry. V2 should replace this with a
//  backend-issued biometric session token.
//

import Foundation
import LocalAuthentication
import Security

struct BiometricCredentialStore: BiometricCredentialStoreProtocol {
  /// Distinct from TokenStorage's service so prod/sandbox split is preserved
  /// and biometric creds aren't co-mingled with tokens.
  private let service: String = AppEnvironment.isProdPlaid
    ? "com.halofi.ios.biometric.prod"
    : "com.halofi.ios.biometric.sandbox"
  private let account = "credentials"

  // MARK: - Existence

  var hasEnrolledCredentials: Bool {
    // iOS 14+ replacement for kSecUseAuthenticationUIFail: pass an LAContext
    // with interactionNotAllowed = true so the keychain refuses to prompt
    // and instead returns errSecInteractionNotAllowed when biometry would
    // be required.
    let context = LAContext()
    context.interactionNotAllowed = true

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecMatchLimit as String: kSecMatchLimitOne,
      // Important: do NOT set kSecReturnData here — that would trigger the
      // biometry prompt. We only want to check for presence.
      kSecUseAuthenticationContext as String: context
    ]

    let status = SecItemCopyMatching(query as CFDictionary, nil)
    // errSecInteractionNotAllowed is the success path here: item exists, but
    // we declined to perform the biometric interaction.
    return status == errSecSuccess || status == errSecInteractionNotAllowed
  }

  // MARK: - Save

  func save(_ credentials: BiometricCredentials) throws {
    let payload = try JSONEncoder().encode(["email": credentials.email,
                                            "password": credentials.password])

    var aclError: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      .biometryCurrentSet,
      &aclError
    ) else {
      if let error = aclError?.takeRetainedValue() {
        Logger.error("Failed to create SecAccessControl: \(error)")
      }
      throw BiometricCredentialError.notAvailable
    }

    let baseQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]

    // Wipe any prior entry so the new ACL replaces the old one cleanly.
    SecItemDelete(baseQuery as CFDictionary)

    var addQuery = baseQuery
    addQuery[kSecValueData as String] = payload
    addQuery[kSecAttrAccessControl as String] = access

    let status = SecItemAdd(addQuery as CFDictionary, nil)
    guard status == errSecSuccess else {
      Logger.error("Failed to save biometric credentials. OSStatus: \(status)")
      throw BiometricCredentialError.keychainError(status)
    }
  }

  // MARK: - Read

  func read(reason: String) async throws -> BiometricCredentials {
    let context = LAContext()
    context.localizedReason = reason

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseAuthenticationContext as String: context
    ]

    // SecItemCopyMatching is blocking when biometry is required; run off the
    // main actor so we don't stall the UI while the OS sheet is up.
    let result: Result<Data, BiometricCredentialError> = await Task.detached(priority: .userInitiated) {
      var item: AnyObject?
      let status = SecItemCopyMatching(query as CFDictionary, &item)

      switch status {
      case errSecSuccess:
        guard let data = item as? Data else {
          return .failure(.encodingError)
        }
        return .success(data)
      case errSecUserCanceled:
        return .failure(.userCancelled)
      case errSecItemNotFound:
        return .failure(.notFound)
      case errSecAuthFailed, errSecDecode:
        // ACL invalidated (biometry re-enrolled) or auth failed.
        return .failure(.biometricsInvalidated)
      default:
        return .failure(.keychainError(status))
      }
    }.value

    switch result {
    case .success(let data):
      guard let dict = try? JSONDecoder().decode([String: String].self, from: data),
            let email = dict["email"],
            let password = dict["password"] else {
        throw BiometricCredentialError.encodingError
      }
      return BiometricCredentials(email: email, password: password)
    case .failure(let error):
      throw error
    }
  }

  // MARK: - Clear

  func clear() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      Logger.error("Failed to clear biometric credentials. OSStatus: \(status)")
    }
  }
}

// MARK: - Mock Implementation for Testing

#if DEBUG
final class MockBiometricCredentialStore: BiometricCredentialStoreProtocol {
  var stored: BiometricCredentials?
  var simulatedReadError: BiometricCredentialError?

  var hasEnrolledCredentials: Bool { stored != nil }

  func save(_ credentials: BiometricCredentials) throws {
    stored = credentials
  }

  func read(reason: String) async throws -> BiometricCredentials {
    if let error = simulatedReadError { throw error }
    guard let creds = stored else { throw BiometricCredentialError.notFound }
    return creds
  }

  func clear() {
    stored = nil
  }
}
#endif
