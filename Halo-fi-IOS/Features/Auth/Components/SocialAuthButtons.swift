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
    /// (idToken, nonce, givenName, familyName). Name is non-nil ONLY on the
    /// very first authorization for this Apple ID — Apple never puts it in
    /// the id_token, so if we don't forward it here it is lost forever and
    /// the account is created as "User".
    let onAppleSignIn: (String, String, String?, String?) -> Void
    let onGoogleSignIn: () -> Void
    /// When the social buttons sit at the bottom of a form, the leading
    /// "or" divider separates them from the form above. When they're
    /// at the top of the form, the divider is meaningless — pass false
    /// and place a divider after this view instead.
    var showsLeadingDivider: Bool = true
    /// Defaults to .signIn so existing SignInView call sites keep their
    /// current copy without a code change.
    var mode: SocialAuthMode = .signIn
    /// Called when Apple sign-in fails for a REAL reason (not a user
    /// cancel). Optional — this view also shows its own alert — so
    /// existing call sites need no change, but a parent can bind this to
    /// clear its own loading state.
    var onAppleSignInError: (String) -> Void = { _ in }

    @State private var currentNonce: String?
    // Scales the Google button label with Dynamic Type instead of a fixed
    // 19pt (App Store Guideline 4). Apple's own button scales already.
    @ScaledMetric(relativeTo: .body) private var googleLabelSize: CGFloat = 19
    // Screen background is `.systemBackground` — pure white in light mode.
    // A `.white` Apple button on it has no visible edge, which is what
    // Guideline 4 flagged ("buttons should be clearly identifiable to
    // users as buttons"). Follow Apple's HIG instead: black-on-light,
    // white-on-dark.
    @Environment(\.colorScheme) private var colorScheme
    /// Non-nil drives a user-visible failure alert. App Store review
    /// (2.1(a)) rejected the build because Apple sign-in failed with no
    /// feedback — the guard below used to `return` silently.
    @State private var appleErrorMessage: String?

    private var appleButtonLabel: SignInWithAppleButton.Label {
        // Apple's HIG: .signIn for returning users, .signUp for new
        // account flows. Both buttons hit the same backend path; this
        // is purely the button title Apple draws for us.
        switch mode {
        case .signIn: return .signIn
        case .signUp: return .signUp
        }
    }

    private var appleButtonStyle: SignInWithAppleButton.Style {
        colorScheme == .dark ? .white : .black
    }

    /// Google's branding guidelines pair the light button with a
    /// #747775 stroke and the dark button with #8E918F. Without the
    /// stroke the light button disappears on a white background the
    /// same way the Apple one did.
    private var googleFill: Color {
        colorScheme == .dark ? Color(red: 0.075, green: 0.075, blue: 0.078) : .white
    }

    private var googleStroke: Color {
        colorScheme == .dark
            ? Color(red: 0.557, green: 0.569, blue: 0.561)
            : Color(red: 0.455, green: 0.463, blue: 0.459)
    }

    private var googleLabelColor: Color {
        colorScheme == .dark ? Color(red: 0.888, green: 0.894, blue: 0.898) : .black
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
                        .fill(Color.haloSeparator)
                        .frame(height: 1)
                    Text("or")
                        .foregroundColor(.haloTextSecondary)
                        .font(.subheadline)
                    Rectangle()
                        .fill(Color.haloSeparator)
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
            .signInWithAppleButtonStyle(appleButtonStyle)
            // The wrapped ASAuthorizationAppleIDButton bakes its style in
            // at creation and ignores later changes — without this, a
            // runtime light/dark switch leaves a black button on a black
            // background. Recreate the button when the scheme flips.
            .id(colorScheme)
            .frame(maxWidth: .infinity)
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
                        .font(.system(size: googleLabelSize, weight: .medium))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .foregroundColor(googleLabelColor)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(googleFill)
                )
                // strokeBorder draws fully inside the shape — a plain
                // .stroke straddles the edge and gets half-clipped by
                // the rounded shape, leaving a hairline.
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(googleStroke, lineWidth: 1)
                )
            }
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1.0)
            .accessibilityLabel(googleButtonText)
        }
        .alert(
            "Sign in with Apple failed",
            isPresented: Binding(
                get: { appleErrorMessage != nil },
                set: { if !$0 { appleErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appleErrorMessage = nil }
        } message: {
            Text(appleErrorMessage ?? "Something went wrong. Please try again.")
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
                // Never fail silently — the reviewer sees a dead button.
                Logger.error("Apple Sign In: missing credential, identity token, or nonce")
                let msg = "We couldn't read your Apple credentials. Please try again."
                appleErrorMessage = msg
                onAppleSignInError(msg)
                return
            }
            // fullName is only populated on the FIRST authorization ever;
            // nil on every subsequent sign-in.
            let givenName = appleIDCredential.fullName?.givenName
            let familyName = appleIDCredential.fullName?.familyName
            onAppleSignIn(idToken, nonce, givenName, familyName)

        case .failure(let error):
            // ASAuthorizationError.canceled is normal (user dismissed) — stay silent.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            Logger.error("Apple Sign In failed: \(error.localizedDescription)")
            let msg = "Apple Sign In couldn't be completed. Please try again."
            appleErrorMessage = msg
            onAppleSignInError(msg)
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
