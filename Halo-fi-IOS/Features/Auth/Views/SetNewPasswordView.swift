//
//  SetNewPasswordView.swift
//  Halo-fi-IOS
//
//  Step 3 of the password reset flow. The user has verified their OTP
//  in ResetPasswordCodeView and we hold a short-lived recovery
//  access_token. This screen collects the new password (with
//  confirmation) and posts it to /auth/set-new-password using the
//  recovery token. On success we pop back to the sign-in screen.
//

import SwiftUI

struct SetNewPasswordView: View {
  // Scales with Dynamic Type (App Store Guideline 4).
  @ScaledMetric(relativeTo: .largeTitle) private var headerIconSize: CGFloat = 60
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager

  let recoveryToken: String
  /// Called when the user taps "Sign In" on the success alert. Threaded
  /// down from ForgotPasswordView so we can dismiss the entire sheet
  /// (popping all three views) and land the user back on SignInView
  /// instead of leaving them stuck on ResetPasswordCodeView.
  var onComplete: (() -> Void)?

  @State private var newPassword = ""
  @State private var confirmPassword = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?
  @State private var showSuccess = false

  private var passwordsMatch: Bool { !newPassword.isEmpty && newPassword == confirmPassword }
  private var passwordIsLongEnough: Bool { newPassword.count >= 8 }
  private var canSubmit: Bool { passwordsMatch && passwordIsLongEnough && !isSubmitting }

  var body: some View {
    ZStack {
      Color.haloBackground.ignoresSafeArea()

      VStack(spacing: 24) {
        VStack(spacing: 16) {
          Image(systemName: "lock.shield")
            .font(.system(size: headerIconSize))
            .foregroundColor(.green)

          Text("New Password")
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundColor(.haloTextPrimary)

          Text("Choose a new password (at least 8 characters).")
            .font(.body)
            .foregroundColor(.haloTextSecondary)
            .multilineTextAlignment(.center)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("New password")
            .font(.headline)
            .foregroundColor(.haloTextPrimary)
          SecureField("Enter new password", text: $newPassword)
            .textFieldStyle(CustomTextFieldStyle())
            .textContentType(.newPassword)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Confirm password")
            .font(.headline)
            .foregroundColor(.haloTextPrimary)
          SecureField("Re-enter new password", text: $confirmPassword)
            .textFieldStyle(CustomTextFieldStyle())
            .textContentType(.newPassword)
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.subheadline)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
        } else if !confirmPassword.isEmpty && !passwordsMatch {
          Text("Passwords don't match")
            .font(.subheadline)
            .foregroundColor(.red)
        }

        Button(action: submit) {
          HStack {
            if isSubmitting {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
            } else {
              Text("Update Password")
                .font(.headline)
                .fontWeight(.semibold)
            }
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 56)
          .background(
            LinearGradient(colors: [Color.purple, Color.indigo],
                           startPoint: .leading, endPoint: .trailing)
          )
          .cornerRadius(16)
        }
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1.0 : 0.6)

        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 40)
    }
    .navigationBarBackButtonHidden(true)
    .alert("Password Updated", isPresented: $showSuccess) {
      Button("Sign In") {
        // Dismiss the entire reset-password sheet so the user lands
        // back on SignInView. Falls back to local dismiss() if no
        // onComplete was supplied (preview/testing).
        if let onComplete {
          onComplete()
        } else {
          dismiss()
        }
      }
    } message: {
      Text("Your password has been updated. You can now sign in with your new password.")
    }
  }

  private func submit() {
    isSubmitting = true
    errorMessage = nil
    Task {
      defer { isSubmitting = false }
      do {
        try await userManager.setNewPassword(
          recoveryAccessToken: recoveryToken,
          newPassword: newPassword
        )
        showSuccess = true
      } catch {
        errorMessage = error.localizedDescription
        Logger.error("Set new password failed: \(error)")
      }
    }
  }
}
