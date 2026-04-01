//
//  SocialAuthButtons.swift
//  Halo-fi-IOS
//
//  Social sign-in buttons for Apple and Google.
//

import SwiftUI
import AuthenticationServices
import CryptoKit

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
            Button(action: onGoogleSignIn) {
                HStack(spacing: 6) {
                    googleLogo
                        .frame(width: 18, height: 18)
                    Text("Sign in with Google")
                        .font(.headline)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white)
                .cornerRadius(16)
            }
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1.0)
            .accessibilityLabel("Sign in with Google")
        }
    }

    // MARK: - Google Logo (official colors)

    private var googleLogo: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let r = min(w, h) / 2

            // Blue (top-right arc)
            var blue = Path()
            blue.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
            blue.addLine(to: CGPoint(x: cx, y: cy))
            blue.closeSubpath()
            context.fill(blue, with: .color(Color(red: 0.255, green: 0.522, blue: 0.957)))

            // Green (bottom-right arc)
            var green = Path()
            green.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(45), endAngle: .degrees(135), clockwise: false)
            green.addLine(to: CGPoint(x: cx, y: cy))
            green.closeSubpath()
            context.fill(green, with: .color(Color(red: 0.204, green: 0.659, blue: 0.325)))

            // Yellow (bottom-left arc)
            var yellow = Path()
            yellow.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(135), endAngle: .degrees(225), clockwise: false)
            yellow.addLine(to: CGPoint(x: cx, y: cy))
            yellow.closeSubpath()
            context.fill(yellow, with: .color(Color(red: 0.984, green: 0.737, blue: 0.22)))

            // Red (top-left arc)
            var red = Path()
            red.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false)
            red.addLine(to: CGPoint(x: cx, y: cy))
            red.closeSubpath()
            context.fill(red, with: .color(Color(red: 0.918, green: 0.263, blue: 0.208)))

            // White center
            var center = Path()
            center.addEllipse(in: CGRect(x: cx - r * 0.55, y: cy - r * 0.55, width: r * 1.1, height: r * 1.1))
            context.fill(center, with: .color(.white))

            // Blue bar (the "G" opening)
            let barRect = CGRect(x: cx - r * 0.05, y: cy - r * 0.15, width: r * 0.65, height: r * 0.3)
            context.fill(Path(barRect), with: .color(Color(red: 0.255, green: 0.522, blue: 0.957)))
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
