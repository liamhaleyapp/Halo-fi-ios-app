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
      // Check if user already has connected accounts before starting flow
      Task {
        // Quick check: if user already has accounts, we shouldn't be here
        // But if we are, check and complete if accounts exist
        do {
          try await bankDataManager.fetchAccounts(forceRefresh: false)
          await MainActor.run {
            let hasAccounts = bankDataManager.accounts?.isEmpty == false
            
            if hasAccounts {
              // User already has accounts - complete onboarding
              userManager.completeOnboarding()
              if let onComplete = onComplete {
                onComplete()
              } else {
                dismiss()
              }
              return
            }
            
            // No accounts - proceed with normal flow
            guard !hasStartedFlow else { return }
            hasStartedFlow = true
            startPlaidFlow()
          }
        } catch {
          // If fetch fails, proceed with normal flow
          await MainActor.run {
            guard !hasStartedFlow else { return }
            hasStartedFlow = true
            startPlaidFlow()
          }
        }
      }
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
      hasStartedFlow = true // Mark as started to prevent restart
    }
    
    do {
      let tokens = [linkSuccess.publicToken]
      print("🔵 Plaid: Starting completion with public token: \(tokens.first?.prefix(20) ?? "nil")...")
      
      // Use sandbox endpoint when in sandbox environment (e.g., "continue as guest")
      // TODO: Detect sandbox mode more reliably - for now, always use sandbox in development
      #if DEBUG
      let linkingResponse = try await bankDataManager.completeLinking(with: tokens, useSandbox: true)
      print("✅ Plaid: Linking response received")
      print("   - Success: \(linkingResponse.success)")
      print("   - Message: \(linkingResponse.message ?? "nil")")
      print("   - Total Items Created: \(linkingResponse.totalItemsCreated ?? -1)")
      print("   - Failed Items: \(linkingResponse.failedItems?.count ?? 0)")
      print("   - All Connected Items: \(linkingResponse.allConnectedItems?.count ?? 0)")
      #else
      let linkingResponse = try await bankDataManager.completeLinking(with: tokens, useSandbox: false)
      print("✅ Plaid: Linking response received")
      print("   - Success: \(linkingResponse.success)")
      print("   - Message: \(linkingResponse.message ?? "nil")")
      print("   - Total Items Created: \(linkingResponse.totalItemsCreated ?? -1)")
      print("   - Failed Items: \(linkingResponse.failedItems?.count ?? 0)")
      print("   - All Connected Items: \(linkingResponse.allConnectedItems?.count ?? 0)")
      #endif
      
      // Verify accounts were actually created before completing
      // Give backend a moment to sync
      print("🔵 Plaid: Waiting 1 second for backend to sync...")
      try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
      
      print("🔵 Plaid: Fetching accounts...")
      try? await bankDataManager.fetchAccounts(forceRefresh: true)
      
      await MainActor.run {
        isCompletingLinking = false
        
        // Double-check that accounts exist before completing
        let accounts = bankDataManager.accounts
        let hasAccounts = accounts?.isEmpty == false
        
        print("🔵 Plaid: Account check results:")
        print("   - Accounts array: \(accounts != nil ? "exists" : "nil")")
        print("   - Accounts count: \(accounts?.count ?? 0)")
        print("   - Has accounts: \(hasAccounts)")
        
        if let accounts = accounts {
          print("   - Account details:")
          for (index, account) in accounts.enumerated() {
            print("     [\(index)] ID: \(account.id), Name: \(account.name), Type: \(account.type)")
          }
        }
        
        if hasAccounts {
          print("✅ Plaid: Accounts found, completing onboarding")
          userManager.completeOnboarding()
          // Call completion handler if provided (for unified onboarding flow)
          // Otherwise dismiss
          if let onComplete = onComplete {
            onComplete()
          } else {
            dismiss()
          }
        } else {
          print("❌ Plaid: No accounts found after linking")
          // Accounts weren't created - show error but don't restart flow
          errorMessage = "Connection completed but accounts weren't found. Please try again."
          showingError = true
          hasStartedFlow = false // Allow retry
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
    
    // Before handling exit, check if user already has accounts
    // (They might have completed connection but exited before success callback)
    do {
      try await bankDataManager.fetchAccounts(forceRefresh: true)
      await MainActor.run {
        let hasAccounts = bankDataManager.accounts?.isEmpty == false
        
        if hasAccounts {
          // User has accounts - complete onboarding even though they exited
          userManager.completeOnboarding()
          if let onComplete = onComplete {
            onComplete()
          } else {
            dismiss()
          }
          return
        }
      }
    } catch {
      // If fetch fails, continue with normal exit handling
    }
    
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
        hasStartedFlow = false // Reset so they can try again if they want
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

