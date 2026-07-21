//
//  BiometricSettingsEnrollmentSheet.swift
//  Halo-fi-IOS
//
//  Enrollment flow invoked from Settings, where the user is already signed in
//  but we never kept their password. Asks for password, validates against the
//  login endpoint to make sure we cache valid credentials, then triggers
//  Face ID / Touch ID and persists to the biometric Keychain.
//

import SwiftUI
import LocalAuthentication

struct BiometricSettingsEnrollmentSheet: View {
  let email: String?
  let biometryType: LABiometryType
  let authService: AuthServiceProtocol
  let biometricAuthService: BiometricAuthService
  let credentialStore: BiometricCredentialStoreProtocol
  let onComplete: (Bool) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var password = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  private var biometryName: String {
    switch biometryType {
    case .faceID: return "Face ID"
    case .touchID: return "Touch ID"
    default: return "biometrics"
    }
  }

  private var iconName: String {
    switch biometryType {
    case .faceID: return "faceid"
    case .touchID: return "touchid"
    default: return "lock.shield"
    }
  }

  private var formattedEmail: String {
    email ?? "—"
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          Image(systemName: iconName)
            .font(.system(size: 56))
            .foregroundStyle(
              LinearGradient(
                colors: [Color.purple, Color.indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .padding(.top, 8)
            .accessibilityHidden(true)

          VStack(spacing: 6) {
            Text("Enable \(biometryName) Sign-in")
              .font(.title2)
              .fontWeight(.bold)
              .accessibilityAddTraits(.isHeader)
            Text("Confirm your password to allow \(biometryName) sign-in.")
              .font(.body)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
          .padding(.horizontal, 16)

          VStack(alignment: .leading, spacing: 8) {
            Text("Phone")
              .font(.caption)
              .foregroundColor(.secondary)
            Text(formattedEmail)
              .font(.body)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
              .background(Color.gray.opacity(0.12))
              .cornerRadius(10)
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("Password")
              .font(.caption)
              .foregroundColor(.secondary)
            SecureField("Enter your password", text: $password)
              .textContentType(.password)
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
              .background(Color.gray.opacity(0.12))
              .cornerRadius(10)
              .accessibilityLabel("Password")
          }

          if let errorMessage {
            Text(errorMessage)
              .font(.caption)
              .foregroundColor(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityLabel("Error: \(errorMessage)")
          }

          Button {
            Task { await submit() }
          } label: {
            HStack {
              if isSubmitting {
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .white))
                  .scaleEffect(0.8)
              } else {
                Text("Enable \(biometryName)")
                  .font(.headline)
                  .fontWeight(.semibold)
              }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
              LinearGradient(
                colors: [Color.purple, Color.indigo],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .cornerRadius(14)
          }
          .disabled(password.isEmpty || email == nil || isSubmitting)
          .opacity((password.isEmpty || email == nil) ? 0.5 : 1.0)

          Spacer(minLength: 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
      }
      .navigationTitle("Enable \(biometryName)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            onComplete(false)
            dismiss()
          }
          .disabled(isSubmitting)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func submit() async {
    guard let rawEmail = email?.trimmingCharacters(in: .whitespaces), !rawEmail.isEmpty else {
      errorMessage = "We don't have an email on your profile. Please contact support."
      return
    }
    guard !password.isEmpty else { return }

    errorMessage = nil
    isSubmitting = true
    defer { isSubmitting = false }

    // Validate the password by calling the login endpoint. New tokens are
    // discarded — the user is already signed in via UserManager and we don't
    // disturb that session.
    do {
      _ = try await authService.login(email: rawEmail, password: password)
    } catch {
      errorMessage = "That password didn't work. Please try again."
      return
    }

    // Confirm intent with biometrics, then persist.
    do {
      try await biometricAuthService.authenticate(reason: "Enable \(biometryName) sign-in")
      try credentialStore.save(BiometricCredentials(email: rawEmail, password: password))
      onComplete(true)
      dismiss()
    } catch BiometricAuthService.BiometricError.cancelled {
      errorMessage = "\(biometryName) was cancelled."
    } catch BiometricAuthService.BiometricError.notAvailable {
      errorMessage = "\(biometryName) isn't available on this device."
    } catch BiometricAuthService.BiometricError.lockedOut {
      errorMessage = "\(biometryName) is locked. Unlock your device with your passcode and try again."
    } catch {
      errorMessage = "Couldn't enable \(biometryName). Please try again."
    }
  }
}
