//
//  SignInView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
import GoogleSignIn
import LocalAuthentication

struct SignInView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager
  @Environment(SubscriptionService.self) private var subscriptionService
  @Environment(DIContainer.self) private var container

  @State private var viewModel = SignInViewModel()
  @State private var showingSignUp = false
  @State private var showingSubscriptionOnboarding = false
  @State private var showingPlaidOnboarding = false
  @State private var showingForgotPassword = false

  /// Tracks whether the auto-prompt-on-phone-field-focus has fired this view
  /// lifecycle. Prevents re-prompting after the user dismisses the OS sheet.
  @State private var hasAttemptedBiometricSignIn = false

  /// Returning OAuth users see only the Apple/Google buttons by default.
  /// Toggling this to false (via the "Use password instead" link) reveals
  /// the full form. Returning password users always start with the form.
  @State private var showOAuthOnlyMode = false

  /// Has the on-appear logic fired yet? Avoids re-running mode detection
  /// (and re-firing Face ID) on subsequent .onAppear from sheet dismissals.
  @State private var hasResolvedAppearMode = false
  
  var body: some View {
    NavigationStack {
    ZStack {
      // Background
      Color.haloBackground.ignoresSafeArea()

      VStack(spacing: 24) {
        // Header
        AuthHeaderView(
          title: "Welcome Back",
          subtitle: "Sign in to continue your financial journey",
          onBackTap: { dismiss() }
        )
        
        // Form — branches based on returning user's last auth method
        Group {
          if showOAuthOnlyMode {
            oauthOnlyContent
          } else {
            fullFormContent
          }
        }
        .padding(.horizontal, 20)

        Spacer()

#if DEBUG
        // Build Info Banner
        Text(AppEnvironment.buildTypeDescription)
          .font(.caption2)
          .foregroundColor(AppEnvironment.isProdPlaid ? .red : .orange)
          .padding(.bottom, 8)
#endif
      }
      .padding(.top, 40)
    }
    .navigationBarHidden(true)
    .fullScreenCover(isPresented: $showingSignUp) {
      SignUpView()
    }
    .sheet(isPresented: $showingForgotPassword) {
      // onComplete dismisses the sheet so the user lands back on
      // SignInView when they finish the reset flow (the flow's
      // pushed views all forward this callback up).
      ForgotPasswordView(onComplete: { showingForgotPassword = false })
    }
    .fullScreenCover(isPresented: $showingSubscriptionOnboarding) {
      SubscriptionOnboardingFlowView()
    }
    .navigationDestination(isPresented: $showingPlaidOnboarding) {
      PlaidOnboardingView(isOnboarding: true)
        .navigationBarTitleDisplayMode(.inline)
    }
    .alert("Sign In Error", isPresented: $viewModel.showingError) {
      Button("OK") { }
    } message: {
      Text(viewModel.errorMessage)
    }
    .sheet(isPresented: $viewModel.showingBiometricEnrollment) {
      BiometricEnrollmentSheet(biometryType: currentBiometryType) { enable in
        Task {
          await viewModel.handleEnrollmentChoice(
            enable: enable,
            biometricAuthService: container.biometricAuthService,
            credentialStore: container.biometricCredentialStore
          )
        }
      }
    }
    .onAppear { resolveAppearMode() }
    } // NavigationStack
  }

  // MARK: - Returning-user mode resolution

  /// Decides how to present the screen based on the user's last auth method.
  /// - Biometric creds enrolled → fire Face ID immediately, regardless of
  ///   last_auth_provider (handles post-reinstall where UserDefaults was wiped
  ///   but the Keychain entry survived)
  /// - apple / google → show OAuth-only layout
  /// - first-time / unknown → show the full form
  private func resolveAppearMode() {
    guard !hasResolvedAppearMode else { return }
    hasResolvedAppearMode = true

    let lastProvider = UserDefaults.standard.string(forKey: "last_auth_provider")

    switch lastProvider {
    case "apple", "google":
      showOAuthOnlyMode = true
    default:
      showOAuthOnlyMode = false
    }

    // Face ID auto-fire is gated only on enrolled creds — independent of the
    // provider flag. This is the universal fast path for any returning user
    // who set up biometrics, including those who just reinstalled the app.
    if container.biometricCredentialStore.hasEnrolledCredentials {
      attemptBiometricSignInIfEnrolled(force: true)
    }
  }

  // MARK: - Form variants

  @ViewBuilder
  private var fullFormContent: some View {
    VStack(spacing: 20) {
      if shouldShowBiometricButton {
        biometricSignInButton
      }

      AuthFormField(
        title: "Email",
        placeholder: "Enter your email",
        text: $viewModel.email,
        keyboardType: .emailAddress,
        textContentType: .username,
        onFocusChange: { isFocused in
          guard isFocused else { return }
          attemptBiometricSignInIfEnrolled()
        }
      )
      if let error = viewModel.emailError {
        validationText(error)
      }

      AuthFormField(
        title: "Password",
        placeholder: "Enter your password",
        text: $viewModel.password,
        isSecure: true,
        textContentType: .password
      )
      if let error = viewModel.passwordError {
        validationText(error)
      }

      // Forgot Password
      HStack {
        Spacer()
        Button("Forgot Password?") {
          showingForgotPassword = true
        }
        .foregroundColor(.blue)
        .font(.body)
        .accessibilityHint("Resets your password")
      }

      AuthButton(
        title: "Sign In",
        isLoading: viewModel.isLoading,
        isEnabled: !viewModel.isLoading,
        action: {
          Task {
            await viewModel.signIn(
              using: userManager,
              subscriptionService: subscriptionService,
              biometricAuthService: container.biometricAuthService,
              biometricCredentialStore: container.biometricCredentialStore,
              onNeedsSubscription: { showingSubscriptionOnboarding = true },
              onNeedsPlaid: { showingPlaidOnboarding = true },
              onSignedInAndOnboarded: { dismiss() }
            )
          }
        }
      )

      // Social Auth
      SocialAuthButtons(
        isLoading: viewModel.isLoading,
        onAppleSignIn: { idToken, nonce in
          Task {
            await viewModel.socialSignIn(
              provider: "apple", idToken: idToken, nonce: nonce,
              using: userManager, subscriptionService: subscriptionService,
              onNeedsSubscription: { showingSubscriptionOnboarding = true },
              onNeedsPlaid: { showingPlaidOnboarding = true },
              onSignedInAndOnboarded: { dismiss() }
            )
          }
        },
        onGoogleSignIn: {
          handleGoogleSignIn()
        }
      )

      signUpLink

#if DEBUG
      SignInDebugMenu(
        quickTestLogin: quickTestLogin,
        mockUserLogin: mockUserLogin,
        testSubscriptionFlow: testSubscriptionFlow,
        testPlaidFlow: testPlaidFlow,
        clearUserData: clearUserData
      )
#endif
    }
  }

  @ViewBuilder
  private var oauthOnlyContent: some View {
    VStack(spacing: 24) {
      Spacer().frame(height: 12)

      SocialAuthButtons(
        isLoading: viewModel.isLoading,
        onAppleSignIn: { idToken, nonce in
          Task {
            await viewModel.socialSignIn(
              provider: "apple", idToken: idToken, nonce: nonce,
              using: userManager, subscriptionService: subscriptionService,
              onNeedsSubscription: { showingSubscriptionOnboarding = true },
              onNeedsPlaid: { showingPlaidOnboarding = true },
              onSignedInAndOnboarded: { dismiss() }
            )
          }
        },
        onGoogleSignIn: {
          handleGoogleSignIn()
        },
        showsLeadingDivider: false
      )

      Button("Use password instead") {
        withAnimation(.easeInOut(duration: 0.2)) {
          showOAuthOnlyMode = false
        }
      }
      .foregroundColor(.blue)
      .font(.body)
      .accessibilityHint("Shows the full sign-in form with phone number and password")

      signUpLink
    }
  }

  @ViewBuilder
  private var signUpLink: some View {
    HStack {
      Text("Don't have an account?")
        .foregroundColor(.haloTextSecondary)

      Button("Sign Up") {
        showingSignUp = true
      }
      .foregroundColor(.blue)
      .accessibilityHint("Creates a new account")
    }
    .font(.body)
  }

  // MARK: - Biometric helpers

  private var currentBiometryType: LABiometryType {
    if case .available(let type) = container.biometricAuthService.currentStatus() {
      return type
    }
    return .none
  }

  private var shouldShowBiometricButton: Bool {
    guard container.biometricCredentialStore.hasEnrolledCredentials else { return false }
    if case .available = container.biometricAuthService.currentStatus() {
      return true
    }
    return false
  }

  @ViewBuilder
  private var biometricSignInButton: some View {
    let label = currentBiometryType == .touchID ? "Sign in with Touch ID" : "Sign in with Face ID"
    let icon = currentBiometryType == .touchID ? "touchid" : "faceid"

    Button {
      attemptBiometricSignInIfEnrolled(force: true)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.title3)
        Text(label)
          .font(.headline)
          .fontWeight(.semibold)
      }
      .foregroundColor(.haloTextPrimary)
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(Color.haloSecondaryBackground)
      .overlay(
        RoundedRectangle(cornerRadius: 14)
          .stroke(Color.haloSeparator, lineWidth: 1)
      )
      .cornerRadius(14)
    }
    .disabled(viewModel.isLoading)
    .accessibilityHint("Authenticates with biometrics and signs in")
  }

  private func attemptBiometricSignInIfEnrolled(force: Bool = false) {
    if !force {
      guard !hasAttemptedBiometricSignIn else { return }
    }
    guard container.biometricCredentialStore.hasEnrolledCredentials else { return }
    hasAttemptedBiometricSignIn = true

    // Resign keyboard so the OS Face ID sheet isn't fighting the keyboard.
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil, from: nil, for: nil
    )

    Task {
      await viewModel.biometricSignIn(
        using: userManager,
        subscriptionService: subscriptionService,
        credentialStore: container.biometricCredentialStore,
        onNeedsSubscription: { showingSubscriptionOnboarding = true },
        onNeedsPlaid: { showingPlaidOnboarding = true },
        onSignedInAndOnboarded: { dismiss() }
      )
    }
  }
  
  @ViewBuilder
  private func validationText(_ message: String) -> some View {
    Text(message)
      .foregroundColor(.red)
      .font(.caption)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityLabel("Error: \(message)")
      .accessibilityAddTraits(.isStaticText)
  }
  
  // MARK: - Social Auth

  private func handleGoogleSignIn() {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let rootViewController = windowScene.windows.first?.rootViewController else {
      return
    }

    Task {
      do {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        guard let idToken = result.user.idToken?.tokenString else {
          viewModel.errorMessage = "Could not get Google ID token."
          viewModel.showingError = true
          return
        }
        await viewModel.socialSignIn(
          provider: "google", idToken: idToken,
          using: userManager, subscriptionService: subscriptionService,
          onNeedsSubscription: { showingSubscriptionOnboarding = true },
          onNeedsPlaid: { showingPlaidOnboarding = true },
          onSignedInAndOnboarded: { dismiss() }
        )
      } catch {
        // GIDSignIn cancellation is code -5
        if (error as NSError).code == -5 { return }
        viewModel.errorMessage = error.localizedDescription.isEmpty
          ? "Unable to sign in with Google. Please try again."
          : error.localizedDescription
        viewModel.showingError = true
      }
    }
  }

  // MARK: - Debug Actions
  private func quickTestLogin() {
    Logger.info("Quick test login triggered")
    Task {
      await MainActor.run {
        // Simulate successful login with mock data
        userManager.isAuthenticated = true
        userManager.currentUser = User(
          id: "debug-user-123",
          email: "test@halofi.com",
          firstName: "Test"
        )
        // Note: Tokens are managed by TokenStorage internally
        // For debug purposes, we're just bypassing authentication
        dismiss()
      }
    }
  }
  
  private func mockUserLogin() {
    Logger.info("Mock user login triggered")
    Task {
      await MainActor.run {
        // Create a more detailed mock user
        userManager.isAuthenticated = true
        userManager.currentUser = User(
          id: "mock-user-456",
          email: "mock@halofi.com",
          firstName: "Mock"
        )
        // Note: Tokens are managed by TokenStorage internally
        // For debug purposes, we're just bypassing authentication
        dismiss()
      }
    }
  }
  
  private func clearUserData() {
    Logger.info("Clearing user data")
    Task {
      await MainActor.run {
        userManager.signOut()
        // Clear form fields
        viewModel.email = ""
        viewModel.password = ""
        viewModel.errorMessage = ""
        viewModel.showingError = false
      }
    }
  }
  
  // MARK: - Debug Onboarding Flow Actions
  func testSubscriptionFlow() {
    Logger.info("Testing subscription onboarding flow")
    // Don't set authentication - just show the flow directly
    // This allows testing without triggering navigation to main app
    showingSubscriptionOnboarding = true
  }
  
  func testPlaidFlow() {
    Logger.info("Testing Plaid onboarding flow")
    // Don't set authentication - just show the flow directly
    // This allows testing without triggering navigation to main app
    showingPlaidOnboarding = true
  }
}

#Preview {
  let container = DIContainer()
  return SignInView()
    .environment(container)
    .environment(container.userManager)
    .environment(SubscriptionService())
}
