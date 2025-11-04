//
//  PlaidManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation
import LinkKit

@MainActor
class PlaidManager: ObservableObject {
  @Published var linkToken: String = ""
  @Published var isCreatingLinkToken = false
  @Published var linkHandler: Handler?
  
  private let networkService = NetworkService.shared
  
  // MARK: - Link Token Creation
  
  func createLinkToken() async throws {
    isCreatingLinkToken = true
    
    defer {
      // Always reset the loading state, even if there's an error
      isCreatingLinkToken = false
    }
    
    let linkTokenRequest = PlaidLinkRequest()
    let requestBody = try JSONEncoder().encode(linkTokenRequest)
    
    let linkResponse: PlaidLinkResponse = try await networkService.authenticatedRequest(
      endpoint: "/bank/multi-link/create",
      method: .POST,
      body: requestBody,
      responseType: PlaidLinkResponse.self
    )
    
    if let error = linkResponse.error {
      throw PlaidError.linkTokenCreationFailed
    }
    
    guard linkResponse.success else {
      throw PlaidError.linkTokenCreationFailed
    }
    
    guard !linkResponse.linkToken.isEmpty else {
      throw PlaidError.linkTokenCreationFailed
    }
    
    linkToken = linkResponse.linkToken
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
    
    configuration.onEvent = { event in
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
}
