//
//  SignUpView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SignUpView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager
  @State private var email = ""
  @State private var password = ""
  @State private var confirmPassword = ""
  @State private var firstName = ""
  @State private var showingSignIn = false
  @State private var showingPlaidOnboarding = false
  @State private var isLoading = false
  
  var body: some View {
    ZStack {
      // Background
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 24) {
        // Header
        AuthHeaderView(
          title: "Create Your Account",
          subtitle: "Join Halo Fi and start your financial journey",
          onBackTap: { dismiss() }
        )
        
        // Form
        VStack(spacing: 20) {
          AuthFormField(
            title: "First Name",
            placeholder: "Enter your first name",
            text: $firstName
          )
          
          AuthFormField(
            title: "Email",
            placeholder: "Enter your email",
            text: $email,
            keyboardType: .emailAddress
          )
          
          AuthFormField(
            title: "Password",
            placeholder: "Create a password",
            text: $password,
            isSecure: true
          )
          
          AuthFormField(
            title: "Confirm Password",
            placeholder: "Confirm your password",
            text: $confirmPassword,
            isSecure: true
          )
          
          AuthButton(
            title: "Create Account",
            isLoading: isLoading,
            isEnabled: isFormValid,
            action: createAccount
          )
          
          // Sign In Link
          HStack {
            Text("Already have an account?")
              .foregroundColor(.gray)
            
            Button("Sign In") {
              showingSignIn = true
            }
            .foregroundColor(.blue)
          }
          .font(.body)
        }
        .padding(.horizontal, 20)
        
        Spacer()
      }
      .padding(.top, 40)
    }
    .navigationBarHidden(true)
    .fullScreenCover(isPresented: $showingSignIn) {
      SignInView()
    }
    .sheet(isPresented: $showingPlaidOnboarding) {
      PlaidOnboardingView()
    }
  }
  
  // MARK: - Form Validation
  private var isFormValid: Bool {
    !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !password.isEmpty &&
    password == confirmPassword &&
    password.count >= 8 &&
    email.contains("@")
  }
  
  // MARK: - Actions
  private func createAccount() {
    Task {
      do {
        try await userManager.signUp(
          email: email,
          password: password,
          firstName: firstName
        )
        showingPlaidOnboarding = true
      } catch {
        // TODO: Show error message
        print("Error creating account: \(error)")
      }
    }
  }
}

#Preview {
  SignUpView()
}
