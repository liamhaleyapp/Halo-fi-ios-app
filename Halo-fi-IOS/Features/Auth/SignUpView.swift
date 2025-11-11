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
  var onComplete: (() -> Void)? = nil
  @State private var email = ""
  @State private var password = ""
  @State private var confirmPassword = ""
  @State private var firstName = ""
  @State private var lastName = ""
  @State private var phoneNumber = ""
  @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
  @State private var showingSignIn = false
  @State private var showingDatePicker = false
  @State private var isLoading = false
  
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
              text: $firstName
            )
            
            AuthFormField(
              title: "Last Name",
              placeholder: "Enter your last name",
              text: $lastName
            )

            DateOfBirthField(selectedDate: dateOfBirth) {
              showingDatePicker = true
            }
            
            AuthFormField(
              title: "Phone Number",
              placeholder: "Enter your phone number",
              text: $phoneNumber,
              keyboardType: .phonePad
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
    }
    .navigationBarHidden(true)
    .fullScreenCover(isPresented: $showingSignIn) {
      SignInView()
    }
    .sheet(isPresented: $showingDatePicker) {
      NavigationView {
        VStack {
          DatePicker(
            "Date of Birth",
            selection: $dateOfBirth,
            in: dateOfBirthRange,
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
  }
  
  // MARK: - Form Validation
  private var isFormValid: Bool {
    !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
    !password.isEmpty &&
    password == confirmPassword &&
    password.count >= 8 &&
    email.contains("@") &&
    isDateOfBirthValid
  }
  
  private var dateOfBirthRange: ClosedRange<Date> {
    let calendar = Calendar.current
    let minDate = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 0)
    let maxDate = Date()
    return minDate...maxDate
  }
  
  private var isDateOfBirthValid: Bool {
    dateOfBirth <= Date()
  }
  
  // MARK: - Actions
  private func createAccount() {
    Task {
      isLoading = true
      
      do {
        // Step 1: Sign up
        try await userManager.signUp(
          firstName: firstName,
          lastName: lastName,
          phone: "+1"+phoneNumber,
          email: email,
          password: password,
          dateOfBirth: dateOfBirth
        )
        
        // Step 2: Auto sign in after successful sign up
        try await userManager.signIn(
          phoneNumber: "+1"+phoneNumber,
          password: password
        )
        
        await MainActor.run {
          isLoading = false
          // User is now authenticated but not onboarded
          // Call completion handler if provided (for onboarding flow)
          // Otherwise MainTabView will detect this and show the appropriate onboarding flow
          if let onComplete = onComplete {
            onComplete()
          }
        }
        
      } catch {
        await MainActor.run {
          isLoading = false
        }
        // TODO: Show error message
        print("Error creating account: \(error)")
      }
    }
  }
}

#Preview {
  SignUpView()
}
