//
//  BiometricAuthService.swift
//  Halo-fi-IOS
//
//  Wraps LocalAuthentication for Face ID / Touch ID flows on the Sign In
//  screen. The Keychain itself enforces biometry on credential reads via
//  SecAccessControl; this service is used to (a) detect availability and
//  (b) explicitly confirm intent during enrollment.
//

import Foundation
import LocalAuthentication

@MainActor
final class BiometricAuthService {
  enum Status: Equatable {
    case notAvailable        // device has no biometry, or user disabled it
    case available(LABiometryType)  // .faceID or .touchID
    case lockedOut           // 5 failed attempts — passcode required to unlock
  }

  enum BiometricError: Error {
    case cancelled
    case userFallback
    case lockedOut
    case notAvailable
    case unknown(Error)
  }

  /// Fresh LAContext per call — Apple recommends this; reusing across
  /// evaluations is undefined.
  func currentStatus() -> Status {
    let context = LAContext()
    var error: NSError?
    let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

    if canEvaluate {
      return .available(context.biometryType)
    }

    if let laError = error as? LAError, laError.code == .biometryLockout {
      return .lockedOut
    }
    return .notAvailable
  }

  /// Triggers the Face ID / Touch ID prompt directly (used at enrollment time).
  /// On the sign-in path, the prompt is triggered implicitly by reading from
  /// the biometric-protected Keychain entry.
  func authenticate(reason: String) async throws {
    let context = LAContext()
    do {
      let success = try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: reason
      )
      guard success else { throw BiometricError.unknown(NSError(domain: "BiometricAuth", code: -1)) }
    } catch let error as LAError {
      switch error.code {
      case .userCancel, .appCancel, .systemCancel:
        throw BiometricError.cancelled
      case .userFallback:
        throw BiometricError.userFallback
      case .biometryLockout:
        throw BiometricError.lockedOut
      case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
        throw BiometricError.notAvailable
      default:
        throw BiometricError.unknown(error)
      }
    } catch {
      throw BiometricError.unknown(error)
    }
  }
}
