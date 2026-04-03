//
//  SocialAuthButtons.swift
//  Halo-fi-IOS
//
//  Social sign-in buttons for Apple and Google.
//

import SwiftUI
import AuthenticationServices
import CryptoKit
import GoogleSignIn

struct SocialAuthButtons: View {
    let isLoading: Bool
    let onAppleSignIn: (String, String) -> Void  // (idToken, nonce)
    let onGoogleSignIn: () -> Void

    @State private var currentNonce: String?

    var body: some View {
        VStack(spacing: 12) {
            // Divider
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

            // Apple Sign In
            SignInWithAppleButton(.signIn) { request in
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
            .accessibilityLabel("Sign in with Apple")

            // Google Sign In
            GoogleSignInButton(style: .wide, scheme: .light) {
                onGoogleSignIn()
            }
            .frame(height: 56)
            .cornerRadius(16)
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1.0)
            .accessibilityLabel("Sign in with Google")
        }
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
