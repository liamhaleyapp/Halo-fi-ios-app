//
//  ForgotPasswordView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//
//  Step 1 of the password reset flow. User picks their channel
//  (email or phone) and submits the identifier. The backend dispatches
//  a 6-digit OTP via the chosen channel; we then navigate to
//  ResetPasswordCodeView to collect the code.
//
//  Phone is the preferred channel for HaloFi's audience (voice-first,
//  blind/low-vision users) because it doesn't require typing an email
//  address and the SMS arrives via the same Twilio path the user already
//  knows from signup verification.
//

import SwiftUI

struct ForgotPasswordView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager

  /// Called once the entire flow finishes (user finished setting a new
  /// password and tapped "Sign In" on the success alert). The presenter
  /// (SignInView) hooks this up to set its showingForgotPassword
  /// binding to false so the sheet dismisses cleanly back to sign-in.
  /// Falls back to dismiss() if not provided.
  var onComplete: (() -> Void)?

  @State private var channel: ResetChannel = .phone
  @State private var email = ""
  @State private var phoneNumber = ""
  @State private var isLoading = false
  @State private var showingError = false
  @State private var errorMessage = ""
  /// Once the backend accepts the request we set this to a non-nil
  /// PasswordResetMethod so the navigationDestination fires. The view
  /// won't gate on confirmed delivery — backend always returns 200
  /// (anti-enumeration), so we navigate optimistically and let the user
  /// enter the code that arrives in their inbox / messages.
  @State private var pendingMethod: PasswordResetMethod?

  /// Local UI state — which radio toggle is selected. Not the same as
  /// PasswordResetMethod (that one carries the identifier value).
  enum ResetChannel: String, CaseIterable, Identifiable {
    case phone
    case email
    var id: String { rawValue }
    var label: String {
      switch self {
      case .phone: return "Phone"
      case .email: return "Email"
      }
    }
  }

  private var canSubmit: Bool {
    switch channel {
    case .phone:
      if case .valid = USPhoneFormatting.validate(phoneNumber) { return true }
      return false
    case .email:
      return !email.trimmingCharacters(in: .whitespaces).isEmpty
    }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 24) {
          VStack(spacing: 16) {
            Image(systemName: "lock.rotation")
              .font(.system(size: 60))
              .foregroundColor(.blue)

            Text("Reset Password")
              .font(.largeTitle)
              .fontWeight(.bold)
              .foregroundColor(.white)

            Text("Choose how you'd like to receive a 6-digit reset code.")
              .font(.body)
              .foregroundColor(.white.opacity(0.85))
              .multilineTextAlignment(.center)
          }

          // Channel picker. Segmented style is the most accessible
          // toggle option here — VoiceOver reads "Phone" / "Email"
          // as distinct values rather than a generic "switch".
          Picker("Reset method", selection: $channel) {
            ForEach(ResetChannel.allCases) { c in
              Text(c.label).tag(c)
            }
          }
          .pickerStyle(.segmented)
          .accessibilityLabel("Reset method")

          // Identifier field — switches based on channel.
          if channel == .phone {
            VStack(alignment: .leading, spacing: 8) {
              Text("Phone")
                .font(.headline)
                .foregroundColor(.white)

              TextField("(555) 555-5555", text: $phoneNumber)
                .textFieldStyle(CustomTextFieldStyle())
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            }
          } else {
            VStack(alignment: .leading, spacing: 8) {
              Text("Email")
                .font(.headline)
                .foregroundColor(.white)

              TextField("Enter your email", text: $email)
                .textFieldStyle(CustomTextFieldStyle())
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
            }
          }

          Button(action: requestReset) {
            HStack {
              if isLoading {
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .white))
                  .scaleEffect(0.8)
              } else {
                Text(channel == .phone ? "Send SMS Code" : "Send Email Code")
                  .font(.headline)
                  .fontWeight(.semibold)
              }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
              LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(16)
          }
          .disabled(isLoading || !canSubmit)
          .opacity(canSubmit ? 1.0 : 0.6)

          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
      }
      .navigationDestination(item: $pendingMethod) { method in
        ResetPasswordCodeView(method: method, onComplete: onComplete ?? { dismiss() })
      }
    }
    .navigationBarHidden(true)
    .alert("Error", isPresented: $showingError) {
      Button("OK") { }
    } message: {
      Text(errorMessage)
    }
  }

  private func requestReset() {
    isLoading = true
    Task {
      defer { isLoading = false }
      do {
        switch channel {
        case .phone:
          guard let fullPhone = USPhoneFormatting.formatForAPI(phoneNumber) else {
            errorMessage = "Invalid phone number format."
            showingError = true
            return
          }
          try await userManager.resetPasswordSMS(phone: fullPhone)
          pendingMethod = .phone(fullPhone)
        case .email:
          let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
          try await userManager.resetPassword(email: trimmedEmail)
          pendingMethod = .email(trimmedEmail)
        }
      } catch {
        errorMessage = "Unable to send reset code. Please check your \(channel.label.lowercased()) and try again."
        showingError = true
        Logger.error("Error resetting password (\(channel.rawValue)): \(error)")
      }
    }
  }
}
