//
//  SocialAuthButtons.swift
//  Halo-fi-IOS
//
//  Social sign-in buttons for Apple and Google.
//

import SwiftUI
import AuthenticationServices
import CryptoKit

/// Whether this set of social buttons is sitting on a sign-in or
/// sign-up screen. Drives the Apple button style (Apple's HIG ships
/// distinct .signIn / .signUp / .continue label styles) and the
/// Google button label text.
enum SocialAuthMode {
    case signIn
    case signUp
}

struct SocialAuthButtons: View {
    let isLoading: Bool
    let onAppleSignIn: (String, String) -> Void  // (idToken, nonce)
    let onGoogleSignIn: () -> Void
    /// When the social buttons sit at the bottom of a form, the leading
    /// "or" divider separates them from the form above. When they're
    /// at the top of the form, the divider is meaningless — pass false
    /// and place a divider after this view instead.
    var showsLeadingDivider: Bool = true
    /// Defaults to .signIn so existing SignInView call sites keep their
    /// current copy without a code change.
    var mode: SocialAuthMode = .signIn

    @State private var currentNonce: String?

    private var appleButtonLabel: SignInWithAppleButton.Label {
        // Apple's HIG: .signIn for returning users, .signUp for new
        // account flows. Both buttons hit the same backend path; this
        // is purely the button title Apple draws for us.
        switch mode {
        case .signIn: return .signIn
        case .signUp: return .signUp
        }
    }

    private var googleButtonText: String {
        switch mode {
        case .signIn: return "Sign in with Google"
        case .signUp: return "Sign up with Google"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsLeadingDivider {
                HStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                    Text("or")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.vertical, 4)
            }

            // Apple Sign In / Sign Up — Apple draws the label based on
            // the .signIn / .signUp style we hand it.
            SignInWithAppleButton(appleButtonLabel) { request in
                let nonce = randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = sha256(nonce)
            } onCompletion: { result in
                handleAppleSignIn(result: result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56)
            .cornerRadius(16)
            .disabled(isLoading)
            .accessibilityLabel(mode == .signUp ? "Sign up with Apple" : "Sign in with Apple")

            // Google Sign In / Sign Up
            Button(action: onGoogleSignIn) {
                HStack(spacing: 6) {
                    googleLogo
                        .frame(width: 18, height: 18)
                    Text(googleButtonText)
                        .font(.system(size: 19, weight: .medium))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white)
                .cornerRadius(16)
            }
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1.0)
            .accessibilityLabel(googleButtonText)
        }
    }

    // MARK: - Google Logo
    // Uses the official g-logo.png from Google's identity branding
    // assets (https://developers.google.com/identity/branding-guidelines).
    // Recreating the mark in code is explicitly disallowed by their
    // brand guidelines — the asset is shipped in Assets.xcassets.

    private var googleLogo: some View {
        Image("GoogleLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .accessibilityHidden(true)
    }

    // MARK: - Apple Sign In Handler

    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = appleIDCredential.identityToken,
                  let idToken = String(data: identityTokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                return
            }
            onAppleSignIn(idToken, nonce)

        case .failure(let error):
            // ASAuthorizationError.canceled is normal (user dismissed)
            if (error as? ASAuthorizationError)?.code != .canceled {
                Logger.error("Apple Sign In failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Nonce Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
