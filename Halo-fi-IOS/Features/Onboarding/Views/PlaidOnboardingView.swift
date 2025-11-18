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
  var onComplete: (() -> Void)? = nil
  var onBack: (() -> Void)? = nil
  @StateObject private var plaidManager = PlaidManager()
  @State private var showingPlaidLink = false
  @State private var showingError = false
  @State private var errorMessage = ""
  @State private var hasStartedFlow = false
  @State private var isDismissing = false
  @State private var shouldSignOut = false
  @State private var isCompletingLinking = false
  
  var body: some View {
    NavigationView {
      ZStack {
        Color(.systemBackground).ignoresSafeArea()
        
        if showingPlaidLink, let handler = plaidManager.linkHandler {
          LinkController(handler: handler)
            .background(Color.black)
        } else if plaidManager.isCreatingLinkToken || isCompletingLinking || bankDataManager.isSyncing {
          PlaidLoadingView()
        } else {
          VStack(spacing: 0) {
            PlaidHeader(onCancel: {
              if let onBack = onBack {
                onBack()
              } else {
                dismiss()
              }
            })
            
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
      Button("OK") {
        handleErrorDismissal()
      }
    } message: {
      Text(errorMessage)
    }
    .onChange(of: shouldSignOut) { oldValue, newValue in
      if newValue {
        handleSignOut()
      }
    }
  }
  
  // MARK: - Plaid Flow Methods
  private func startPlaidFlow() {
    Task {
      do {
        // Step 1: Create link token
        try await plaidManager.createLinkToken()
        
        // Step 2: Create Plaid handler with callbacks
        guard plaidManager.createHandler(
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
        ) != nil else {
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
              shouldSignOut = true
            case .invalidCredentials:
              errorMessage = "Invalid credentials. Please sign in again."
              shouldSignOut = true
            case .serverError(let code):
              errorMessage = "Server error (\(code)). Please try again later."
            case .networkError:
              errorMessage = "Network connection failed. Please check your internet connection."
            case .validationError:
              errorMessage = "Invalid request. Please try again."
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
    // Show loading indicator
    await MainActor.run {
      isCompletingLinking = true
      showingPlaidLink = false // Hide Plaid Link UI
    }
    
    do {
      let tokens = [linkSuccess.publicToken]
      // Use sandbox endpoint when in sandbox environment (e.g., "continue as guest")
      // TODO: Detect sandbox mode more reliably - for now, always use sandbox in development
      #if DEBUG
      _ = try await bankDataManager.completeLinking(with: tokens, useSandbox: true)
      #else
      _ = try await bankDataManager.completeLinking(with: tokens, useSandbox: false)
      #endif
      
      await MainActor.run {
        isCompletingLinking = false
        userManager.completeOnboarding()
        // Call completion handler if provided (for unified onboarding flow)
        // Otherwise dismiss
        if let onComplete = onComplete {
          onComplete()
        } else {
          dismiss()
        }
      }
    } catch {
      await MainActor.run {
        isCompletingLinking = false
        
        // Check if it's an authentication error
        if let authError = error as? AuthError {
          switch authError {
          case .tokenExpired, .invalidCredentials:
            errorMessage = authError.errorDescription ?? "Your session has expired. Please sign in again."
            shouldSignOut = true
          default:
            errorMessage = "Failed to complete connection: \(authError.localizedDescription)"
          }
        } else if let bankError = error as? BankError {
          // Use the bank error's description
          errorMessage = bankError.errorDescription ?? "Failed to complete connection: \(error.localizedDescription)"
        } else {
          errorMessage = "Failed to complete connection: \(error.localizedDescription)"
        }
        showingError = true
      }
    }
  }
  
  private func handleErrorDismissal() {
    // Reset state after dismissing error
    showingPlaidLink = false
    hasStartedFlow = false
    
    // If we need to sign out, do it after a brief delay to allow alert to dismiss
    if shouldSignOut {
      Task {
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        await MainActor.run {
          handleSignOut()
        }
      }
    }
  }
  
  private func handleSignOut() {
    // Sign out the user
    // This will trigger onChange in UnifiedOnboardingFlowView if we're in unified flow
    // Or MainTabView will handle showing sign in screen if we're standalone
    userManager.signOut()
    
    // If we're in unified flow, the onChange handler will dismiss
    // If we're standalone, dismiss this view
    if onBack == nil && onComplete == nil {
      // Standalone mode - dismiss this view
      dismiss()
    }
    // In unified flow, UnifiedOnboardingFlowView will handle dismissal via onChange
  }
  
  private func handlePlaidExit(_ linkExit: LinkExit?) async {
    // Reset Plaid Link view state first to hide the LinkController
    await MainActor.run {
      showingPlaidLink = false
    }
    
    // Small delay to ensure the view updates before showing error or dismissing
    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
    
    // Check if there's an error that needs to be shown
    let hasError = linkExit?.error != nil
    
    await MainActor.run {
      if hasError {
        // Handle specific exit scenarios with errors
        let errorMessage = switch linkExit?.error?.errorCode {
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
          linkExit?.error?.errorMessage ?? "Connection failed"
        @unknown default:
          linkExit?.error?.errorMessage ?? "Connection failed"
        }
        
        self.errorMessage = errorMessage
        showingError = true
        hasStartedFlow = false // Reset so user can try again
      } else {
        // User cancelled without error - go back or dismiss
        isDismissing = true
        if let onBack = onBack {
          onBack()
        } else {
          dismiss()
        }
      }
    }
  }
}

#Preview {
  PlaidOnboardingView()
    .environment(UserManager())
    .environment(BankDataManager())
}

