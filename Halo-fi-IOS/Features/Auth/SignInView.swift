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
  @State private var email = ""
  @State private var password = ""
  @State private var showingSignUp = false
  @State private var isLoading = false
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
            title: "Email",
            placeholder: "Enter your email",
            text: $email,
            keyboardType: .emailAddress
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
  }
  
  // MARK: - Form Validation
  private var isFormValid: Bool {
    !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !password.isEmpty
  }
  
  // MARK: - Actions
  private func signIn() {
    Task {
      do {
        try await userManager.signIn(email: email, password: password)
        dismiss()
      } catch {
        // TODO: Show error message
        print("Error signing in: \(error)")
      }
    }
  }
}

#Preview {
  SignInView()
}
