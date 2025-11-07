//
//  PlaidOnboardingView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
import LinkKit

struct PlaidOnboardingView: View {
  @SwiftUI.Environment(\.dismiss) private var dismiss
  @SwiftUI.Environment(UserManager.self) private var userManager
  @StateObject private var plaidManager = PlaidManager()
  @State private var showingPlaidLink = false
  @State private var showingError = false
  @State private var errorMessage = ""
  
  // Feature flag to bypass Plaid - set to true to skip Plaid flow
  private let bypassPlaid: Bool = true
  
  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        // Header
        PlaidHeader(onCancel: { dismiss() })
        
        // Plaid Link Interface
        if bypassPlaid {
          // Bypass mode - show skip button
          bypassPlaidView
        } else if plaidManager.isCreatingLinkToken {
          PlaidLoadingView()
        } else if showingPlaidLink, let handler = plaidManager.linkHandler {
          LinkController(handler: handler)
        } else {
          // Fallback view if something goes wrong
          VStack(spacing: 20) {
            Text("Ready to connect your bank account")
              .font(.title2)
              .foregroundColor(.white)
            
            Button("Start Connection") {
              startPlaidFlow()
            }
            .foregroundStyle(.white)
            .padding()
            .background(Color.blue)
            .cornerRadius(10)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(
            LinearGradient(
              colors: [Color.indigo, Color.purple],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
        }
      }
      .navigationBarHidden(true)
    }
    .onAppear {
      if bypassPlaid {
        // Automatically skip Plaid and mark onboarding complete
        // Small delay to prevent view flashing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          handleBypassPlaid()
        }
      } else {
        startPlaidFlow()
      }
    }
    .alert("Connection Error", isPresented: $showingError) {
      Button("OK") { }
    } message: {
      Text(errorMessage)
    }
  }
  
  // MARK: - Bypass Plaid View
  private var bypassPlaidView: some View {
    VStack(spacing: 24) {
      Spacer()
      
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 80))
        .foregroundColor(.green)
      
      Text("Plaid Bypassed")
        .font(.title)
        .fontWeight(.bold)
        .foregroundColor(.white)
      
      Text("You can connect your bank account later from the Accounts section.")
        .font(.body)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
      
      Spacer()
      
      Button("Continue") {
        handleBypassPlaid()
      }
      .font(.headline)
      .foregroundColor(.white)
      .frame(maxWidth: .infinity)
      .padding()
      .background(
        LinearGradient(
          colors: [Color.blue, Color.purple],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .cornerRadius(12)
      .padding(.horizontal, 40)
      .padding(.bottom, 40)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
  }
  
  // MARK: - Bypass Handler
  private func handleBypassPlaid() {
    // Mark onboarding as complete without going through Plaid
    userManager.completeOnboarding()
    dismiss()
  }
  
  // MARK: - Plaid Flow Methods
  private func startPlaidFlow() {
    Task {
      do {
        // Step 1: Create link token
        try await plaidManager.createLinkToken()
        
        // Step 2: Create Plaid handler with callbacks
        guard let handler = plaidManager.createHandler(
          onSuccess: { linkSuccess in
            Task { @MainActor in
              await handlePlaidSuccess(linkSuccess)
            }
          },
          onExit: { linkExit in
            Task { @MainActor in
              await handlePlaidExit(linkExit)
            }
          }
        ) else {
          throw PlaidError.linkTokenCreationFailed
        }
        
        // Step 3: Show Plaid Link interface
        await MainActor.run {
          showingPlaidLink = true
        }
      } catch {
        await MainActor.run {
          // Provide more specific error messages
          if let authError = error as? AuthError {
            switch authError {
            case .tokenExpired:
              errorMessage = "Your session has expired. Please sign in again."
            case .serverError(let code):
              errorMessage = "Server error (\(code)). Please try again later."
            case .networkError:
              errorMessage = "Network connection failed. Please check your internet connection."
            case .validationError:
              errorMessage = "Invalid request. Please try again."
            case .invalidCredentials:
              errorMessage = "Invalid credentials. Please sign in again."
            case .emailAlreadyExists:
              errorMessage = "An account with this email already exists."
            case .unknownError:
              errorMessage = "An unknown error occurred. Please try again."
            }
          } else {
            errorMessage = "Failed to start bank connection: \(error.localizedDescription)"
          }
          showingError = true
        }
      }
    }
  }
  
  private func handlePlaidSuccess(_ linkSuccess: LinkSuccess) async {
    do {
      // Exchange the public token with your backend
      try await plaidManager.exchangePublicToken(linkSuccess.publicToken)
      
      // Mark onboarding as complete
      await MainActor.run {
        userManager.completeOnboarding()
        dismiss()
      }
    } catch {
      await MainActor.run {
        errorMessage = "Failed to complete connection: \(error.localizedDescription)"
        showingError = true
      }
    }
  }
  
  private func handlePlaidExit(_ linkExit: LinkExit?) async {
    if let linkExit = linkExit {
      // Handle specific exit scenarios
      let errorMessage = switch linkExit.error?.errorCode {
      case .apiError(let apiError):
        "API Error: \(apiError)"
      case .authError(let authError):
        "Authentication Error: \(authError)"
      case .itemError(let itemError):
        "Item Error: \(itemError)"
      case .invalidInput(let inputError):
        "Invalid Input: \(inputError)"
      case .invalidRequest(let requestError):
        "Invalid Request: \(requestError)"
      case .rateLimitExceeded(let rateLimitError):
        "Rate Limit Exceeded: \(rateLimitError)"
      case .institutionError(let institutionError):
        "Institution Error: \(institutionError)"
      case .assetReportError(let assetError):
        "Asset Report Error: \(assetError)"
      case .internal(let internalError):
        "Internal Error: \(internalError)"
      case .unknown(let type, let code):
        "Unknown Error: \(type) - \(code)"
      case .none:
        linkExit.error?.errorMessage ?? "Connection failed"
      }
      
      await MainActor.run {
        self.errorMessage = errorMessage
        showingError = true
      }
    } else {
      // User cancelled without error - just dismiss
      await MainActor.run {
        dismiss()
      }
    }
  }
}

