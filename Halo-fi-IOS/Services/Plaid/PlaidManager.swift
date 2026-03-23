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

  /// Stored link_session_id from Plaid onEvent callback (for multi-item link webhook routing)
  private(set) var linkSessionId: String?
  /// Flag indicating if session has been registered with backend
  private(set) var isSessionRegistered = false

  private let networkService = NetworkService.shared
  private let bankService = BankService.shared
  
  // MARK: - Configuration (DIRECT_LINK_BYPASS Mode)

#if DIRECT_LINK_BYPASS
  // Direct create mode: items are created directly without Link UI
  // Only available in builds with DIRECT_LINK_BYPASS flag (Debug, TF-Sandbox)
  var sandboxResponse: BankMultiConnectResponse?
  var isSandboxDirectMode: Bool = false
#endif
  
  // MARK: - Link Token Creation
  
  func createLinkToken() async throws {
    isCreatingLinkToken = true
    defer { isCreatingLinkToken = false }

    let linkTokenRequest = PlaidLinkRequest()
    let requestBody = try JSONEncoder().encode(linkTokenRequest)

    #if DIRECT_LINK_BYPASS
    // Runtime safety guard (backup to compile-time #error)
    guard AppEnvironment.plaidEnv == .sandbox else {
      assertionFailure("Direct bypass should never run in production")
      throw PlaidError.linkTokenCreationFailed
    }

    // Direct create mode - bypass Link UI entirely
    // Step 1: Create the link first (this creates the PlaidUser on the backend)
    Logger.debug("PlaidManager: Starting link token creation (DIRECT MODE)")
    Logger.debug("PlaidManager: Step 1 - Creating link to establish PlaidUser")
    Logger.debug("PlaidManager: Endpoint: /bank/multi-link/create")

    do {
      let linkResponse: PlaidLinkResponse = try await networkService.authenticatedRequest(
        endpoint: "/bank/multi-link/create",
        method: .POST,
        body: requestBody,
        responseType: PlaidLinkResponse.self
      )

      Logger.debug("PlaidManager: Link creation - success: \(linkResponse.success)")

      guard linkResponse.success else {
        Logger.debug("PlaidManager: Link creation failed")
        throw PlaidError.linkTokenCreationFailed
      }

      // Step 2: Now create sandbox items (PlaidUser now exists)
      Logger.debug("PlaidManager: Step 2 - Creating sandbox items")
      Logger.debug("PlaidManager: Endpoint: /bank/sandbox/create-multi-items")

      let sandboxResponse: BankMultiConnectResponse = try await networkService.authenticatedRequest(
        endpoint: "/bank/sandbox/create-multi-items",
        method: .POST,
        body: requestBody,
        responseType: BankMultiConnectResponse.self
      )

      Logger.debug("PlaidManager: Sandbox response received - success: \(sandboxResponse.success)")
      Logger.debug("PlaidManager: Total items created: \(sandboxResponse.totalItemsCreated ?? 0)")

      guard sandboxResponse.success else {
        Logger.debug("PlaidManager: Sandbox response success is false")
        throw PlaidError.linkTokenCreationFailed
      }

      self.sandboxResponse = sandboxResponse
      self.isSandboxDirectMode = true
      Logger.debug("PlaidManager: Items created directly - proceeding without Link UI")
    } catch {
      Logger.debug("PlaidManager: Error in direct mode - \(error.localizedDescription)")
      throw error
    }

    #else
    // Standard Link UI mode
    Logger.debug("PlaidManager: Starting link token creation (LINK UI MODE)")
    Logger.debug("PlaidManager: Environment: \(AppEnvironment.plaidEnv)")
    Logger.debug("PlaidManager: Endpoint: /bank/multi-link/create")

    do {
      let linkResponse: PlaidLinkResponse = try await networkService.authenticatedRequest(
        endpoint: "/bank/multi-link/create",
        method: .POST,
        body: requestBody,
        responseType: PlaidLinkResponse.self
      )

      Logger.debug("PlaidManager: Link token creation - success: \(linkResponse.success)")

      if let error = linkResponse.error {
        Logger.debug("PlaidManager: Response error: \(error)")
        throw PlaidError.linkTokenCreationFailed
      }

      guard linkResponse.success, !linkResponse.linkToken.isEmpty else {
        Logger.debug("PlaidManager: Link token creation failed")
        throw PlaidError.linkTokenCreationFailed
      }

      linkToken = linkResponse.linkToken
      Logger.debug("PlaidManager: Link token stored successfully")
    } catch {
      Logger.debug("PlaidManager: Error creating link token - \(error.localizedDescription)")
      throw error
    }
    #endif
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
    
    // Capture link_session_id for multi-item link webhook routing
    configuration.onEvent = { [weak self] event in
      Logger.debug("PlaidManager: onEvent callback triggered")
      Task { @MainActor in
        self?.handleLinkEvent(event)
      }
    }

    Logger.debug("PlaidManager: Handler configuration created with onEvent callback")

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
  
  // MARK: - Link Event Handling (Multi-Item Link)

  /// Handles Plaid Link events, capturing link_session_id for webhook routing
  private func handleLinkEvent(_ event: LinkEvent) {
    let eventName = String(describing: event.eventName)

    // Log error events
    if eventName.lowercased().contains("error") {
      Logger.error("PlaidManager: Link error event: \(event.metadata)")
    }

    // Capture link_session_id from event metadata (available on all events)
    let sessionId = event.metadata.linkSessionID
    guard !sessionId.isEmpty else {
      Logger.warning("PlaidManager: linkSessionID is empty, skipping registration")
      return
    }

    // Only register once per session
    guard linkSessionId != sessionId else {
      Logger.debug("PlaidManager: Session already registered, skipping")
      return
    }

    linkSessionId = sessionId
    Logger.info("PlaidManager: Captured link_session_id: \(sessionId.prefix(20))...")

    // Register with backend for webhook routing (fire and forget)
    Task {
      await registerLinkSessionWithBackend(sessionId: sessionId)
    }
  }

  /// Registers link_session_id with backend for webhook routing
  private func registerLinkSessionWithBackend(sessionId: String) async {
    guard !isSessionRegistered else { return }

    do {
      try await bankService.registerLinkSession(sessionId: sessionId)
      isSessionRegistered = true
      Logger.success("PlaidManager: Link session registered with backend")
    } catch {
      // Non-fatal - webhooks may still work via other mechanisms
      Logger.warning("PlaidManager: Failed to register link session: \(error.localizedDescription)")
    }
  }

  // MARK: - Security: Clear Sensitive Data

  /// Clears all Plaid session state
  /// SECURITY: Should be called when Plaid Link session ends (success, cancel, or error)
  func clearSession() {
    linkHandler = nil
    linkToken = ""
    isCreatingLinkToken = false
    linkSessionId = nil
    isSessionRegistered = false
#if DIRECT_LINK_BYPASS
    sandboxResponse = nil
    isSandboxDirectMode = false
#endif
    Logger.debug("PlaidManager: Session cleared")
  }
}
