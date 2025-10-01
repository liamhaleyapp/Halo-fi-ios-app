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
        headerView
        
        // Form
        VStack(spacing: 20) {
          firstNameField
          emailField
          passwordField
          confirmPasswordField
          
          createAccountButton
          
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
      
      Text("Create Your Account")
        .font(.largeTitle)
        .fontWeight(.bold)
        .foregroundColor(.white)
      
      Text("Join Halo Fi and start your financial journey")
        .font(.body)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
    }
  }
  
  // MARK: - Form Fields
  private var firstNameField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("First Name")
        .font(.headline)
        .foregroundColor(.white)
      
      TextField("Enter your first name", text: $firstName)
        .textFieldStyle(CustomTextFieldStyle())
        .autocapitalization(.words)
    }
  }
  
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
      
      SecureField("Create a password", text: $password)
        .textFieldStyle(CustomTextFieldStyle())
    }
  }
  
  private var confirmPasswordField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Confirm Password")
        .font(.headline)
        .foregroundColor(.white)
      
      SecureField("Confirm your password", text: $confirmPassword)
        .textFieldStyle(CustomTextFieldStyle())
    }
  }
  
  // MARK: - Create Account Button
  private var createAccountButton: some View {
    Button(action: createAccount) {
      HStack {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .scaleEffect(0.8)
        } else {
          Text("Create Account")
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

// MARK: - Custom Text Field Style
struct CustomTextFieldStyle: TextFieldStyle {
  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .background(Color.gray.opacity(0.2))
      .cornerRadius(12)
      .foregroundColor(.white)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.gray.opacity(0.3), lineWidth: 1)
      )
  }
}

#Preview {
  SignUpView()
}
