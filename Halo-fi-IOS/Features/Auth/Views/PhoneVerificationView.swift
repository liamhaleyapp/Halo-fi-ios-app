//
//  PhoneVerificationView.swift
//  Halo-fi-IOS
//
//  Step 2 of the email/password signup flow. After the user submits
//  their details and the backend creates the account with phone_confirm
//  = false, Supabase sends an SMS OTP via Twilio. The user enters the
//  6-digit code here; on success we pop back to SignUpView which then
//  signs them in.
//
//  Apple/Google signups skip this entirely — they go through
//  AuthService.social_login on the backend which auto-confirms.
//

import SwiftUI

struct PhoneVerificationView: View {
  // Scales with Dynamic Type (App Store Guideline 4).
  @ScaledMetric(relativeTo: .largeTitle) private var headerIconSize: CGFloat = 60
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager

  /// Supabase user_auth_id returned from /users/signup. Required for
  /// both verify and resend.
  let idUser: String
  /// Display-only — used to remind the user which number they should
  /// be checking. We don't reformat it server-side; pass the same E.164
  /// string we used in the signup call.
  let phone: String
  /// True if the backend confirmed it dispatched the initial SMS. False
  /// means the user should immediately tap "Resend" — the SMS provider
  /// failed silently during signup.
  let smsAlreadySent: Bool
  /// Called once /auth/verification_code returns success. The parent
  /// (SignUpViewModel.completePhoneVerification) takes it from here.
  var onVerified: () -> Void

  @State private var code = ""
  @State private var isVerifying = false
  @State private var isResending = false
  @State private var errorMessage: String?
  @State private var resendCooldownSeconds = 0
  @State private var resendTimer: Timer?

  private let resendCooldownDuration = 30

  var body: some View {
    ZStack {
      Color.haloBackground.ignoresSafeArea()

      VStack(spacing: 24) {
        VStack(spacing: 16) {
          Image(systemName: "iphone.radiowaves.left.and.right")
            .font(.system(size: headerIconSize))
            .foregroundColor(.blue)

          Text("Verify Your Phone")
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundColor(.haloTextPrimary)

          Text("We sent a 6-digit code to \(phone). Enter it below to finish creating your account.")
            .font(.body)
            .foregroundColor(.haloTextSecondary)
            .multilineTextAlignment(.center)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Code")
            .font(.headline)
            .foregroundColor(.haloTextPrimary)

          TextField("123456", text: $code)
            .textFieldStyle(CustomTextFieldStyle())
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .onChange(of: code) { _, newValue in
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
              Text("Verify")
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

        Button(action: resend) {
          if isResending {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .blue))
          } else if resendCooldownSeconds > 0 {
            Text("Resend code in \(resendCooldownSeconds)s")
              .foregroundColor(.haloTextSecondary)
          } else {
            Text("Didn't get a code? Resend")
              .foregroundColor(.blue)
          }
        }
        .disabled(isResending || resendCooldownSeconds > 0)

        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 40)
    }
    .navigationBarBackButtonHidden(false)
    .onAppear {
      // If the backend reported the initial SMS dispatch succeeded, we
      // start with a cooldown to prevent spam-clicking resend. If it
      // failed silently, leave the resend button live so the user can
      // request one immediately.
      if smsAlreadySent {
        startResendCooldown()
      }
    }
    .onDisappear {
      resendTimer?.invalidate()
    }
  }

  private func verify() {
    isVerifying = true
    errorMessage = nil
    Task {
      defer { isVerifying = false }
      do {
        try await userManager.verifyPhoneOTP(idUser: idUser, code: code)
        onVerified()
        dismiss()
      } catch {
        errorMessage = "That code didn't work. Check your messages and try again."
        Logger.error("Phone OTP verify failed: \(error)")
      }
    }
  }

  private func resend() {
    isResending = true
    errorMessage = nil
    Task {
      defer { isResending = false }
      do {
        try await userManager.resendPhoneOTP(idUser: idUser)
        startResendCooldown()
      } catch {
        errorMessage = "Couldn't resend the code. Try again in a moment."
        Logger.error("Phone OTP resend failed: \(error)")
      }
    }
  }

  private func startResendCooldown() {
    resendCooldownSeconds = resendCooldownDuration
    resendTimer?.invalidate()
    resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
      Task { @MainActor in
        if resendCooldownSeconds > 0 {
          resendCooldownSeconds -= 1
        } else {
          timer.invalidate()
        }
      }
    }
  }
}
