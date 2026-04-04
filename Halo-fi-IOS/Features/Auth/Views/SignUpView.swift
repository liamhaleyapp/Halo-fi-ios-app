//
//  SignUpView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
import GoogleSignIn

struct SignUpView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager
  @Environment(SubscriptionService.self) private var subscriptionService

  var onComplete: (() -> Void)?
  
  @State private var viewModel = SignUpViewModel()
  @State private var showingSignIn = false
  @State private var showingDatePicker = false
  @State private var showingSubscriptionOnboarding = false
  @State private var showingPlaidOnboarding = false
  @State private var agreedToTerms = false
  @State private var showingTerms = false
  @State private var showingPrivacy = false

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
              text: $viewModel.firstName,
              textContentType: .givenName
            )
            if let error = viewModel.firstNameError {
              validationText(error)
            }
            
            AuthFormField(
              title: "Last Name",
              placeholder: "Enter your last name",
              text: $viewModel.lastName,
              textContentType: .familyName
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
              keyboardType: .phonePad,
              textContentType: .username
            )
            if let error = viewModel.phoneError {
              validationText(error)
            }
            
            AuthFormField(
              title: "Email",
              placeholder: "Enter your email",
              text: $viewModel.email,
              keyboardType: .emailAddress,
              textContentType: .emailAddress
            )
            if let error = viewModel.emailError {
              validationText(error)
            }
            
            AuthFormField(
              title: "Password",
              placeholder: "Create a password",
              text: $viewModel.password,
              isSecure: true,
              textContentType: .newPassword
            )
            if let error = viewModel.passwordError {
              validationText(error)
            }
            
            AuthFormField(
              title: "Confirm Password",
              placeholder: "Confirm your password",
              text: $viewModel.confirmPassword,
              isSecure: true,
              textContentType: .newPassword
            )
            if let error = viewModel.confirmPasswordError {
              validationText(error)
            }
            
            // Terms & Privacy consent
            HStack(alignment: .top, spacing: 12) {
              Button {
                agreedToTerms.toggle()
              } label: {
                Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                  .font(.title3)
                  .foregroundColor(agreedToTerms ? .indigo : .gray)
              }
              .accessibilityLabel(agreedToTerms ? "Terms accepted" : "Accept terms")
              .accessibilityHint("Toggle to agree to Terms of Service and Privacy Policy")

              Text("I agree to the ") .foregroundColor(.gray) .font(.caption) +
              Text("Terms of Service") .foregroundColor(.blue) .font(.caption) .underline() +
              Text(" and ") .foregroundColor(.gray) .font(.caption) +
              Text("Privacy Policy") .foregroundColor(.blue) .font(.caption) .underline()
            }
            .onTapGesture { location in
              // Rough hit detection for the links
              // Full width tap toggles checkbox; we rely on the sheets below
            }
            .overlay(
              HStack(spacing: 0) {
                Color.clear.frame(width: 40) // checkbox area
                Button { showingTerms = true } label: { Color.clear }
                  .frame(width: 110)
                Color.clear.frame(width: 30) // "and" text
                Button { showingPrivacy = true } label: { Color.clear }
                  .frame(width: 100)
                Spacer()
              }
              .frame(height: 20)
              , alignment: .leading
            )
            .padding(.top, 4)

            AuthButton(
              title: "Create Account",
              isLoading: viewModel.isLoading,
              isEnabled: !viewModel.isLoading && agreedToTerms,
              action: {
                Task {
                  await viewModel.createAccount(using: userManager, onComplete: onComplete)
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
                    onSignedInAndOnboarded: { onComplete?(); dismiss() }
                  )
                }
              },
              onGoogleSignIn: {
                handleGoogleSignIn()
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
    .sheet(isPresented: $showingTerms) {
      LegalDocumentView(
        title: "Terms of Service",
        sections: AboutView.termsOfServiceSections,
        endpoint: APIEndpoints.Legal.terms
      )
    }
    .sheet(isPresented: $showingPrivacy) {
      LegalDocumentView(
        title: "Privacy Policy",
        sections: AboutView.privacyPolicySections,
        endpoint: APIEndpoints.Legal.privacy
      )
    }
    .fullScreenCover(isPresented: $showingSubscriptionOnboarding) {
      SubscriptionOnboardingFlowView()
    }
    .navigationDestination(isPresented: $showingPlaidOnboarding) {
      PlaidOnboardingView(isOnboarding: true)
        .navigationBarTitleDisplayMode(.inline)
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
          .datePickerStyle(.graphical)
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
      .presentationDetents([.large])
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
          onSignedInAndOnboarded: { onComplete?(); dismiss() }
        )
      } catch {
        if (error as NSError).code == -5 { return }
        viewModel.errorMessage = error.localizedDescription.isEmpty
          ? "Unable to sign up with Google. Please try again."
          : error.localizedDescription
        viewModel.showingError = true
      }
    }
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
