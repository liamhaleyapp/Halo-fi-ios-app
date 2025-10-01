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
        headerView
        
        // Form
        VStack(spacing: 20) {
          emailField
          passwordField
          
          // Forgot Password
          HStack {
            Spacer()
            Button("Forgot Password?") {
              showingForgotPassword = true
            }
            .foregroundColor(.blue)
            .font(.body)
          }
          
          signInButton
          
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
  
  // MARK: - Header View
  private var headerView: some View {
    VStack(spacing: 16) {
      // Back Arrow
      HStack {
        Button(action: {
          dismiss()
        }) {
          Image(systemName: "chevron.left")
            .font(.title2)
            .foregroundColor(.white)
            .padding(8)
            .background(Color.white.opacity(0.2))
            .clipShape(Circle())
        }
        
        Spacer()
      }
      .padding(.horizontal, 20)
      
      // App Logo/Icon
      Circle()
        .fill(LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: 80, height: 80)
        .overlay(
          Image(systemName: "mic.circle.fill")
            .font(.system(size: 40))
            .foregroundColor(.white)
        )
      
      Text("Welcome Back")
        .font(.largeTitle)
        .fontWeight(.bold)
        .foregroundColor(.white)
      
      Text("Sign in to continue your financial journey")
        .font(.body)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
    }
  }
  
  // MARK: - Form Fields
  private var emailField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Email")
        .font(.headline)
        .foregroundColor(.white)
      
      TextField("Enter your email", text: $email)
        .textFieldStyle(CustomTextFieldStyle())
        .keyboardType(.emailAddress)
        .autocapitalization(.none)
    }
  }
  
  private var passwordField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Password")
        .font(.headline)
        .foregroundColor(.white)
      
      SecureField("Enter your password", text: $password)
        .textFieldStyle(CustomTextFieldStyle())
    }
  }
  
  // MARK: - Sign In Button
  private var signInButton: some View {
    Button(action: signIn) {
      HStack {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .scaleEffect(0.8)
        } else {
          Text("Sign In")
            .font(.headline)
            .fontWeight(.semibold)
        }
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .background(
        LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .leading, endPoint: .trailing)
      )
      .cornerRadius(16)
    }
    .disabled(isLoading || !isFormValid)
    .opacity(isFormValid ? 1.0 : 0.6)
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

// MARK: - Forgot Password View


#Preview {
  SignInView()
}
