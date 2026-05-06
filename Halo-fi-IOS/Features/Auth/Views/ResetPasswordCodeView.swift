//
//  ResetPasswordCodeView.swift
//  Halo-fi-IOS
//
//  Step 2 of the password reset flow. User has just received a 6-digit
//  OTP via either email (Supabase template uses {{ .Token }}) or SMS
//  (Twilio + Supabase). They enter the code here; on success we
//  navigate to SetNewPasswordView with the short-lived recovery access
//  token returned by the backend.
//
//  The screen is parameterized by `method` so the same view powers both
//  the email-reset and SMS-reset paths — only the verify call and the
//  on-screen copy differ.
//

import SwiftUI

/// Identifies which channel a password reset OTP was sent through.
/// Carries the identifier (email address or phone number) needed to
/// verify the code with the backend.
enum PasswordResetMethod: Hashable {
  case email(String)
  case phone(String)

  /// Identifier as used in the backend request body.
  var identifier: String {
    switch self {
    case .email(let e): return e
    case .phone(let p): return p
    }
  }

  /// Used in user-facing copy: "We sent a code to <identifier>".
  var displayValue: String { identifier }

  /// "email" / "phone" — used in copy fragments and a11y labels.
  var channelName: String {
    switch self {
    case .email: return "email"
    case .phone: return "phone"
    }
  }

  /// SF Symbol that decorates the screen.
  var iconName: String {
    switch self {
    case .email: return "envelope.badge"
    case .phone: return "iphone.radiowaves.left.and.right"
    }
  }
}

struct ResetPasswordCodeView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager

  let method: PasswordResetMethod

  @State private var code = ""
  @State private var isVerifying = false
  @State private var errorMessage: String?
  @State private var navigateToSetPassword = false
  @State private var recoveryToken: String?

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 24) {
        VStack(spacing: 16) {
          Image(systemName: method.iconName)
            .font(.system(size: 60))
            .foregroundColor(.blue)

          Text("Enter Code")
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundColor(.white)

          Text("We sent a 6-digit code to your \(method.channelName) (\(method.displayValue)).")
            .font(.body)
            .foregroundColor(.white.opacity(0.85))
            .multilineTextAlignment(.center)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Code")
            .font(.headline)
            .foregroundColor(.white)

          TextField("123456", text: $code)
            .textFieldStyle(CustomTextFieldStyle())
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .onChange(of: code) { _, newValue in
              // Cap to 6 digits — strip non-numeric.
              let digits = newValue.filter { $0.isNumber }
              if digits != newValue || digits.count > 6 {
                code = String(digits.prefix(6))
              }
            }
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.subheadline)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
        }

        Button(action: verify) {
          HStack {
            if isVerifying {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
            } else {
              Text("Verify Code")
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
        .disabled(isVerifying || code.count != 6)
        .opacity(code.count != 6 ? 0.6 : 1.0)

        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 40)
    }
    .navigationBarBackButtonHidden(false)
    .navigationDestination(isPresented: $navigateToSetPassword) {
      if let recoveryToken {
        SetNewPasswordView(recoveryToken: recoveryToken)
      }
    }
  }

  private func verify() {
    isVerifying = true
    errorMessage = nil
    Task {
      defer { isVerifying = false }
      do {
        let token: String
        switch method {
        case .email(let email):
          token = try await userManager.verifyPasswordResetOTP(email: email, code: code)
        case .phone(let phone):
          token = try await userManager.verifyPasswordResetSMSOTP(phone: phone, code: code)
        }
        recoveryToken = token
        navigateToSetPassword = true
      } catch {
        errorMessage = "That code didn't work. Check your \(method.channelName) and try again."
        Logger.error("Reset OTP verify failed (\(method.channelName)): \(error)")
      }
    }
  }
}
