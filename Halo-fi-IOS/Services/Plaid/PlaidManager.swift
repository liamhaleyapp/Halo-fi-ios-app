//
//  PlaidManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation
import LinkKit

@MainActor
@Observable
class PlaidManager {
  var linkToken: String = ""
  var isCreatingLinkToken = false
  var linkHandler: Handler?
  
  private let networkService = NetworkService.shared
  
  // MARK: - Configuration (DEBUG ONLY - Sandbox Mode)
  
#if DEBUG
  // Sandbox direct mode: when items are created directly without Link UI
  // ⚠️ DEBUG ONLY - This code will not compile in release builds
  var sandboxResponse: BankMultiConnectResponse?
  var isSandboxDirectMode: Bool = false
  
  /// ⚠️ DEBUG ONLY - Sandbox mode configuration
  /// This flag and all sandbox code is wrapped in #if DEBUG to prevent
  /// accidental inclusion in production builds.
  /// 
  /// Set to `true` for sandbox testing, `false` for production
  /// 
  /// - **Sandbox mode** (`true`): Uses `/bank/sandbox/create-multi-items` endpoint
  ///   - Creates items directly, returns `BankMultiConnectResponse`
  ///   - Bypasses Plaid Link UI and proceeds directly to onboarding completion
  ///   - Use this for testing when you want to skip the Link UI flow
  /// 
  /// - **Production mode** (`false`): Uses `/bank/multi-link/create` endpoint
  ///   - Returns link token for Plaid Link UI, returns `PlaidLinkResponse`
  ///   - Standard production flow with Plaid Link SDK
  private let useSandboxMode = true
#endif
  
  // MARK: - Link Token Creation
  
  func createLinkToken() async throws {
    isCreatingLinkToken = true
    
    defer {
      // Always reset the loading state, even if there's an error
      isCreatingLinkToken = false
    }
    
    let linkTokenRequest = PlaidLinkRequest()
    let requestBody = try JSONEncoder().encode(linkTokenRequest)
    
    if let requestJSON = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any] {
      print("   Request body: \(requestJSON)")
    }
    
    print("   Request body size: \(requestBody.count) bytes")
    
#if DEBUG
    if useSandboxMode {
      // MARK: - Sandbox Path (DEBUG ONLY)
      // 
      // ⚠️ DEBUG ONLY - This code will not compile in release builds
      // Sandbox endpoint: POST /bank/sandbox/create-multi-items
      // Response: BankMultiConnectResponse (items, public_tokens, access_tokens, total_items_created)
      // 
      // ⚠️ IMPORTANT NOTE: This endpoint creates items DIRECTLY without going through Plaid Link UI.
      // It does NOT return a link_token, so the Plaid Link UI flow cannot proceed.
      // 
      // If you need to test the Plaid Link UI flow in sandbox mode, you have two options:
      // 1. Set useSandboxMode = false (use production endpoint with sandbox Plaid credentials)
      // 2. Check if your backend has a sandbox link token endpoint (e.g., /bank/sandbox/multi-link/create)
      // 
      // The /bank/sandbox/create-multi-items endpoint is intended for testing scenarios where
      // you want to bypass the Link UI and create items directly (e.g., automated testing).
      
      print("🔵 PlaidManager: Starting link token creation (SANDBOX MODE - DEBUG ONLY)")
      print("   Endpoint: /bank/sandbox/create-multi-items")
      print("   ⚠️ NOTE: This endpoint creates items directly and doesn't return a link_token")
      
      do {
        let sandboxResponse: BankMultiConnectResponse = try await networkService.authenticatedRequest(
          endpoint: "/bank/sandbox/create-multi-items",
          method: .POST,
          body: requestBody,
          responseType: BankMultiConnectResponse.self
        )
        
        print("✅ PlaidManager: Sandbox response received")
        print("   Response success: \(sandboxResponse.success)")
        print("   Total items created: \(sandboxResponse.totalItemsCreated ?? 0)")
        print("   Items count: \(sandboxResponse.items?.count ?? 0)")
        
        guard sandboxResponse.success else {
          print("❌ PlaidManager: Sandbox response success is false")
          throw PlaidError.linkTokenCreationFailed
        }
        
        // Store sandbox response and enable direct mode (bypasses Link UI)
        // The onboarding flow will detect this and proceed directly to account fetching
        self.sandboxResponse = sandboxResponse
        self.isSandboxDirectMode = true
        
        print("✅ PlaidManager: Sandbox items created directly - proceeding without Link UI")
        print("   Onboarding will fetch accounts and complete automatically")
      } catch {
        print("❌ PlaidManager: Error in sandbox mode")
        print("   Error type: \(type(of: error))")
        print("   Error description: \(error.localizedDescription)")
        if let authError = error as? AuthError {
          print("   AuthError case: \(authError)")
        }
        throw error
      }
      return
    }
    
    // Reset sandbox mode flags when using production (DEBUG only)
    isSandboxDirectMode = false
    sandboxResponse = nil
#endif
    
    // MARK: - Production Path
    // Production endpoint: POST /bank/multi-link/create
    // Response: PlaidLinkResponse (link_token, expires_at, message, error)
    // Standard flow: Get link token → Show Plaid Link UI → Exchange public token
    
    print("🔵 PlaidManager: Starting link token creation (PRODUCTION MODE)")
    print("   Endpoint: /bank/multi-link/create")
      
      do {
        let linkResponse: PlaidLinkResponse = try await networkService.authenticatedRequest(
          endpoint: "/bank/multi-link/create",
          method: .POST,
          body: requestBody,
          responseType: PlaidLinkResponse.self
        )
        
        print("✅ PlaidManager: Link token creation successful")
        print("   Response success: \(linkResponse.success)")
        print("   Link token length: \(linkResponse.linkToken.count) characters")
        print("   Expires at: \(linkResponse.expiresAt)")
        
        if let error = linkResponse.error {
          print("   Response error: \(error)")
        }
      
        if linkResponse.error != nil {
          print("❌ PlaidManager: Response contains error")
          throw PlaidError.linkTokenCreationFailed
        }
        
        guard linkResponse.success else {
          print("❌ PlaidManager: Response success is false")
          throw PlaidError.linkTokenCreationFailed
        }
        
        guard !linkResponse.linkToken.isEmpty else {
          print("❌ PlaidManager: Link token is empty")
          throw PlaidError.linkTokenCreationFailed
        }
        
        linkToken = linkResponse.linkToken
        print("✅ PlaidManager: Link token stored successfully")
      } catch {
        print("❌ PlaidManager: Error creating link token")
        print("   Error type: \(type(of: error))")
        print("   Error description: \(error.localizedDescription)")
        if let authError = error as? AuthError {
          print("   AuthError case: \(authError)")
        }
        throw error
      }
  }
  
  // MARK: - Plaid Handler Creation
  
  func createHandler(
    onSuccess: @escaping (LinkSuccess) -> Void,
    onExit: @escaping (LinkExit?) -> Void
  ) -> Handler? {
    guard !linkToken.isEmpty else {
      return nil
    }
    
    // Create the configuration with the link token and callbacks
    var configuration = LinkTokenConfiguration(token: linkToken) { success in
      onSuccess(success)
    }
    
    configuration.onExit = { exit in
      onExit(exit)
    }
    
    configuration.onEvent = { _ in
      // Handle Plaid events if needed
    }
    
    // Create the handler using Plaid.create
    let result = Plaid.create(configuration)
    switch result {
    case .success(let handler):
      linkHandler = handler
      return handler
    case .failure:
      return nil
    }
  }
  
  // MARK: - Public Token Exchange
  
  func exchangePublicToken(_ publicToken: String) async throws {
    // In a real app, this would call your backend to exchange the public token
    // for an access token and fetch initial account data
    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
    
    // Simulate successful exchange
  }
  
  // MARK: - Redirect URL Handling
  
  /// Handles OAuth redirect URLs from Plaid
  /// This should be called when the app receives a redirect URL (e.g., halofi://plaid-oauth?...)
  /// - Parameter url: The redirect URL received from Plaid
  /// - Returns: True if the URL is a valid Plaid redirect URL, false otherwise
  func handleRedirectURL(_ url: URL) -> Bool {
    // Check if the URL is a Plaid OAuth redirect
    // LinkKit automatically handles OAuth redirects when the handler is active
    // This method just validates that it's a Plaid redirect URL
    let isPlaidRedirect = (url.scheme == "halofi" || url.scheme == "plaid") &&
                          (url.host == "plaid-oauth" || url.host == "oauth")
    
    // If we have an active handler, LinkKit will automatically process the redirect
    // when the handler processes the OAuth flow. The redirect URL is passed to the handler
    // through the system's URL handling mechanism.
    return isPlaidRedirect
  }
  
  // MARK: - Security: Clear Sensitive Data
  
  /// Clears link token from memory after use
  /// SECURITY: Should be called when Plaid Link session ends to clear sensitive data
  func clearLinkToken() {
    linkToken = ""
    linkHandler = nil
  }
}
