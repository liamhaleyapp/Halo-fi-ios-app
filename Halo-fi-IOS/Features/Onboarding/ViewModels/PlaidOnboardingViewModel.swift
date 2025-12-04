//
//  PlaidOnboardingViewModel.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/1/25.
//

import SwiftUI
import LinkKit

@MainActor
@Observable
class PlaidOnboardingViewModel {
  
  // State
  var showingPlaidLink = false
  var showingError = false
  var errorMessage = ""
  var hasStartedFlow = false
  var isDismissing = false
  var shouldSignOut = false
  var isCompletingLinking = false
  
  var isLoading: Bool {
    plaidManager.isCreatingLinkToken || isCompletingLinking
  }
  
  // Callbacks (set by view)
  var onComplete: (() -> Void)? = nil
  var onBack: (() -> Void)? = nil
  var onDismiss: (() -> Void)? = nil
  
  let plaidManager = PlaidManager()
  var linkHandler: Handler? { plaidManager.linkHandler }
  
  // MARK: - Public Methods
  
  func startPlaidFlow(bankDataManager: BankDataManager, userManager: UserManager) {
    Task {
      do {
        // Step 1: Create link token (or create items directly in sandbox mode)
        try await plaidManager.createLinkToken()
        
#if DEBUG
        // Check if we're in sandbox direct mode (items created directly, no Link UI)
        // ⚠️ DEBUG ONLY - This code will not compile in release builds
        if plaidManager.isSandboxDirectMode, let sandboxResponse = plaidManager.sandboxResponse {
          // Sandbox path: Items were created directly, skip Link UI and proceed to onboarding
          await handleSandboxDirectMode(
            sandboxResponse: sandboxResponse,
            bankDataManager: bankDataManager,
            userManager: userManager
          )
          return
        }
#endif
        
        // Production path: Use Plaid Link UI
        // Step 2: Create Plaid handler with callbacks
        guard plaidManager.createHandler(
          onSuccess: { linkSuccess in
            Task { @MainActor in
              await self.handlePlaidSuccess(linkSuccess,
                                            bankDataManager: bankDataManager,
                                            userManager: userManager)
            }
          },
          onExit: { linkExit in
            Task { @MainActor in
              await self.handlePlaidExit(linkExit,
                                         bankDataManager: bankDataManager,
                                         userManager: userManager)
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
  
  // MARK: - Sandbox Direct Mode Handler (DEBUG ONLY)
  
#if DEBUG
  /// Handles the sandbox direct mode flow where items are created directly without Plaid Link UI
  /// ⚠️ DEBUG ONLY - This method will not compile in release builds
  /// 
  /// In sandbox mode, items are created directly by the backend. We don't need to fetch accounts
  /// immediately - accounts can be fetched later in AccountsView using the item IDs from the response.
  /// The sandbox response contains item IDs that can be used with `GET /bank/{item_id}/account`.
  private func handleSandboxDirectMode(
    sandboxResponse: BankMultiConnectResponse,
    bankDataManager: BankDataManager,
    userManager: UserManager
  ) async {
    print("🔵 Plaid (Sandbox Direct): Items created directly, completing onboarding")
    print("   - Total items created: \(sandboxResponse.totalItemsCreated ?? 0)")
    print("   - Items count: \(sandboxResponse.items?.count ?? 0)")
    
    // Log created items for reference (accounts can be fetched later using these item IDs)
    if let items = sandboxResponse.items {
      print("   - Created items:")
      for (index, item) in items.enumerated() {
        print("     [\(index)] Item ID: \(item.itemId), Institution: \(item.institutionName)")
      }
    }
    
    // Store linked items in BankDataManager for display in AccountsView
    // The sandbox response has items in a different format, so we map them to ConnectedItem
    if let connectedItems = sandboxResponse.allConnectedItems {
      bankDataManager.linkedItems = connectedItems
      print("✅ Plaid (Sandbox Direct): Stored \(connectedItems.count) linked items in BankDataManager")
    }
    
    // In sandbox mode, items are created directly - no need to fetch accounts now
    // Accounts can be fetched on-demand in AccountsView using GET /bank/{item_id}/account
    await MainActor.run {
      isCompletingLinking = false
      hasStartedFlow = true
      
      print("✅ Plaid (Sandbox Direct): Items created successfully, completing onboarding")
      print("   Accounts will be fetched on-demand in AccountsView")
      
      userManager.completeOnboarding()
      if let onComplete = onComplete {
        onComplete()
      } else {
        onDismiss?()
      }
    }
  }
#endif
  
  private func handlePlaidSuccess(_ linkSuccess: LinkSuccess, bankDataManager: BankDataManager, userManager: UserManager) async {
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
          // Call completion handler if provided (for unified onboarding flow)
          // Otherwise use dismiss callback
          if let onComplete = onComplete {
            onComplete()
          } else {
            onDismiss?()
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
  
  private func handlePlaidExit(_ linkExit: LinkExit?, bankDataManager: BankDataManager, userManager: UserManager) async {
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
            onDismiss?()
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
          onDismiss?()
        }
      }
    }
  }
  
  func handleErrorDismissal(userManager: UserManager) {
    // Reset state after dismissing error
    showingPlaidLink = false
    hasStartedFlow = false
    
    // If we need to sign out, do it after a brief delay to allow alert to dismiss
    if shouldSignOut {
      Task {
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        await MainActor.run {
          handleSignOut(userManager: userManager)
        }
      }
    }
  }
  
  func handleSignOut(userManager: UserManager) {
    // Sign out the user
    // This will trigger onChange in UnifiedOnboardingFlowView if we're in unified flow
    // Or MainTabView will handle showing sign in screen if we're standalone
    userManager.signOut()
    
    // If we're in unified flow, the onChange handler will dismiss
    // If we're standalone, use dismiss callback
    if onBack == nil && onComplete == nil {
      // Standalone mode - dismiss this view
      onDismiss?()
    }
    // In unified flow, UnifiedOnboardingFlowView will handle dismissal via onChange
  }
  
  func bootstrapIfNeeded(userManager: UserManager, bankDataManager: BankDataManager) async {
    guard !hasStartedFlow else { return }
    
    do {
      try await bankDataManager.fetchAccounts(forceRefresh: false)
      let hasAccounts = bankDataManager.accounts?.isEmpty == false
      
      if hasAccounts {
        userManager.completeOnboarding()
        onComplete?() ?? onDismiss?()
        return
      }
      
      hasStartedFlow = true
      startPlaidFlow(bankDataManager: bankDataManager, userManager: userManager)
      
    } catch {
      hasStartedFlow = true
      startPlaidFlow(bankDataManager: bankDataManager, userManager: userManager)
    }
  }
}
