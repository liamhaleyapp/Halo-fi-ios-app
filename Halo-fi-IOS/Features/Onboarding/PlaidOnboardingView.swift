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
  @SwiftUI.Environment(BankDataManager.self) private var bankDataManager
  @StateObject private var plaidManager = PlaidManager()
  @State private var showingPlaidLink = false
  @State private var showingError = false
  @State private var errorMessage = ""
  @State private var hasStartedFlow = false
  
  var body: some View {
    NavigationView {
      ZStack {
        Color(.systemBackground).ignoresSafeArea()
        
        if plaidManager.isCreatingLinkToken {
          PlaidLoadingView()
        } else if showingPlaidLink, let handler = plaidManager.linkHandler {
          LinkController(handler: handler)
        } else {
          VStack(spacing: 0) {
            PlaidHeader(onCancel: { dismiss() })
            
            VStack(spacing: 20) {
              Text("Ready to connect your bank account")
                .font(.title2)
                .foregroundColor(.white)
              
              Button("Start Connection") {
                startPlaidFlow()
              }
              .font(.headline)
              .foregroundColor(.white)
              .padding()
              .background(
                RoundedRectangle(cornerRadius: 12)
                  .fill(Color.blue)
              )
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
      }
      .navigationBarHidden(true)
    }
    .onAppear {
      guard !hasStartedFlow else { return }
      hasStartedFlow = true
      startPlaidFlow()
    }
    .alert("Connection Error", isPresented: $showingError) {
      Button("OK") { }
    } message: {
      Text(errorMessage)
    }
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
      let tokens = [linkSuccess.publicToken]
      _ = try await bankDataManager.completeLinking(with: tokens)
      
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

