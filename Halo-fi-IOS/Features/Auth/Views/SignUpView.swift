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
  
  var onComplete: (() -> Void)?
  
  @State private var viewModel = SignUpViewModel()
  @State private var showingSignIn = false
  @State private var showingDatePicker = false

  var body: some View {
    ZStack {
      // Background
      Color.black.ignoresSafeArea()
      
      ScrollView {
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
              text: $viewModel.firstName
            )
            if let error = viewModel.firstNameError {
              validationText(error)
            }
            
            AuthFormField(
              title: "Last Name",
              placeholder: "Enter your last name",
              text: $viewModel.lastName
            )
            
            DateOfBirthField(selectedDate: viewModel.dateOfBirth) {
              showingDatePicker = true
            }
            if let error = viewModel.dateOfBirthError {
              validationText(error)
            }
            
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
              title: "Email",
              placeholder: "Enter your email",
              text: $viewModel.email,
              keyboardType: .emailAddress
            )
            if let error = viewModel.emailError {
              validationText(error)
            }
            
            AuthFormField(
              title: "Password",
              placeholder: "Create a password",
              text: $viewModel.password,
              isSecure: true
            )
            if let error = viewModel.passwordError {
              validationText(error)
            }
            
            AuthFormField(
              title: "Confirm Password",
              placeholder: "Confirm your password",
              text: $viewModel.confirmPassword,
              isSecure: true
            )
            if let error = viewModel.confirmPasswordError {
              validationText(error)
            }
            
            AuthButton(
              title: "Create Account",
              isLoading: viewModel.isLoading,
              isEnabled: !viewModel.isLoading,
              action: {
                Task {
                  await viewModel.createAccount(using: userManager, onComplete: onComplete)
                }
              }
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
    }
    .navigationBarHidden(true)
    .fullScreenCover(isPresented: $showingSignIn) {
      SignInView()
    }
    .sheet(isPresented: $showingDatePicker) {
      NavigationStack {
        VStack {
          DatePicker(
            "Date of Birth",
            selection: $viewModel.dateOfBirth,
            in: viewModel.dateOfBirthRange,
            displayedComponents: .date
          )
          .datePickerStyle(.wheel)
          .labelsHidden()
          .padding()
          
          Spacer()
        }
        .background(Color.black)
        .navigationTitle("Select Date of Birth")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") {
              showingDatePicker = false
            }
            .foregroundColor(.blue)
          }
        }
      }
      .presentationDetents([.medium])
    }
    .alert("Sign Up Error", isPresented: $viewModel.showingError) {
      Button("OK") { }
    } message: {
      Text(viewModel.errorMessage)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Create your account")
    .accessibilityHint("Step 1 of 3 in the setup process")
  }
  
  // Small helper so all error labels look consistent
  @ViewBuilder
  private func validationText(_ message: String) -> some View {
    Text(message)
      .foregroundColor(.red)
      .font(.caption)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#Preview {
  SignUpView()
    .environment(UserManager())
}
