//
//  SignInView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SignInView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager
  @Environment(SubscriptionService.self) private var subscriptionService
  
  @State private var viewModel = SignInViewModel()
  @State private var showingSignUp = false
  @State private var showingSubscriptionOnboarding = false
  @State private var showingPlaidOnboarding = false
  @State private var showingForgotPassword = false
  
  var body: some View {
    ZStack {
      // Background
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 24) {
        // Header
        AuthHeaderView(
          title: "Welcome Back",
          subtitle: "Sign in to continue your financial journey",
          onBackTap: { dismiss() }
        )
        
        // Form
        VStack(spacing: 20) {
          AuthFormField(
            title: "Phone Number",
            placeholder: "Enter your phone number",
            text: $viewModel.phoneNumber,
            keyboardType: .phonePad
          )
          if let error = viewModel.phoneError {
            validationText(error)
          }
          
          AuthFormField(
            title: "Password",
            placeholder: "Enter your password",
            text: $viewModel.password,
            isSecure: true
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
                  onNeedsSubscription: { showingSubscriptionOnboarding = true },
                  onNeedsPlaid: { showingPlaidOnboarding = true },
                  onSignedInAndOnboarded: { dismiss() }
                )
              }
            }
          )
          
          // Sign Up Link
          HStack {
            Text("Don't have an account?")
              .foregroundColor(.gray)
            
            Button("Sign Up") {
              showingSignUp = true
            }
            .foregroundColor(.blue)
            .accessibilityHint("Creates a new account")
          }
          .font(.body)
          
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
        .padding(.horizontal, 20)

        Spacer()

#if DEBUG || TESTFLIGHT
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
      ForgotPasswordView()
    }
    .fullScreenCover(isPresented: $showingSubscriptionOnboarding) {
      SubscriptionOnboardingFlowView()
    }
    .fullScreenCover(isPresented: $showingPlaidOnboarding) {
      PlaidOnboardingView()
    }
    .alert("Sign In Error", isPresented: $viewModel.showingError) {
      Button("OK") { }
    } message: {
      Text(viewModel.errorMessage)
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
        viewModel.phoneNumber = ""
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
  SignInView()
    .environment(UserManager())
    .environment(SubscriptionService())
}
