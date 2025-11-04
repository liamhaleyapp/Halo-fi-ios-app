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
  @State private var phoneNumber = ""
  @State private var password = ""
  @State private var showingSignUp = false
  @State private var showingSubscriptionOnboarding = false
  @State private var showingPlaidOnboarding = false
  @State private var isLoading = false
  @State private var showingForgotPassword = false
  @State private var errorMessage = ""
  @State private var showingError = false
  
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
            text: $phoneNumber,
            keyboardType: .phonePad
          )
          
          AuthFormField(
            title: "Password",
            placeholder: "Enter your password",
            text: $password,
            isSecure: true
          )
          
          // Forgot Password
          HStack {
            Spacer()
            Button("Forgot Password?") {
              showingForgotPassword = true
            }
            .foregroundColor(.blue)
            .font(.body)
          }
          
          AuthButton(
            title: "Sign In",
            isLoading: isLoading,
            isEnabled: isFormValid,
            action: signIn
          )
          
          // Sign Up Link
          HStack {
            Text("Don't have an account?")
              .foregroundColor(.gray)
            
            Button("Sign Up") {
              showingSignUp = true
            }
            .foregroundColor(.blue)
          }
          .font(.body)
          
          // Debug Section (only in development)
          #if DEBUG
          VStack(spacing: 12) {
            Divider()
              .background(Color.gray.opacity(0.3))
            
            Text("DEBUG MENU")
              .font(.caption)
              .foregroundColor(.orange)
              .fontWeight(.bold)
            
            VStack(spacing: 8) {
              Button("🚀 Quick Test Login") {
                quickTestLogin()
              }
              .foregroundColor(.green)
              .font(.caption)
              
              Button("👤 Mock User Login") {
                mockUserLogin()
              }
              .foregroundColor(.blue)
              .font(.caption)
              
              Button("💳 Test Subscription Flow") {
                testSubscriptionFlow()
              }
              .foregroundColor(.purple)
              .font(.caption)
              
              Button("🏦 Test Plaid Flow") {
                testPlaidFlow()
              }
              .foregroundColor(.cyan)
              .font(.caption)
              
              Button("🔧 Clear User Data") {
                clearUserData()
              }
              .foregroundColor(.red)
              .font(.caption)
            }
          }
          .padding(.top, 10)
          #endif
        }
        .padding(.horizontal, 20)
        
        Spacer()
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
    .alert("Sign In Error", isPresented: $showingError) {
      Button("OK") { }
    } message: {
      Text(errorMessage)
    }
  }
  
  // MARK: - Form Validation
  private var isFormValid: Bool {
    !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !password.isEmpty
  }
  
  // MARK: - Actions
  private func signIn() {
    Task {
      do {
        let phoneNum = "+1"+phoneNumber
        try await userManager.signIn(phoneNumber: phoneNum, password: password)
        
        // Check if user has completed onboarding
        if let user = userManager.currentUser, user.isOnboarded {
          // User is fully onboarded - just dismiss
          await MainActor.run {
            dismiss()
          }
        } else {
          // User needs to complete onboarding
          // Check subscription status
          await subscriptionService.initialize()
          
          await MainActor.run {
            if subscriptionService.hasActiveSubscription {
              // Has subscription - go to Plaid
              showingPlaidOnboarding = true
            } else {
              // No subscription - go to subscription flow
              showingSubscriptionOnboarding = true
            }
          }
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
          showingError = true
        }
      }
    }
  }
  
  // MARK: - Debug Actions
  private func quickTestLogin() {
    print("🚀 DEBUG: Quick test login triggered")
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
    print("👤 DEBUG: Mock user login triggered")
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
    print("🔧 DEBUG: Clearing user data")
    Task {
      await MainActor.run {
        userManager.signOut()
        // Clear form fields
        phoneNumber = ""
        password = ""
        errorMessage = ""
        showingError = false
      }
    }
  }
  
  // MARK: - Debug Onboarding Flow Actions
  private func testSubscriptionFlow() {
    print("💳 DEBUG: Testing subscription onboarding flow")
    // Don't set authentication - just show the flow directly
    // This allows testing without triggering navigation to main app
    showingSubscriptionOnboarding = true
  }
  
  private func testPlaidFlow() {
    print("🏦 DEBUG: Testing Plaid onboarding flow")
    // Don't set authentication - just show the flow directly
    // This allows testing without triggering navigation to main app
    showingPlaidOnboarding = true
  }
}

#Preview {
  SignInView()
}
