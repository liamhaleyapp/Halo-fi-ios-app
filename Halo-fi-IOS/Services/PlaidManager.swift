//
//  PlaidManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

@MainActor
class PlaidManager: ObservableObject {
  @Published var linkToken: String = ""
  private let networkService = NetworkService.shared
  
  func createLinkToken() async throws {
    let linkTokenRequest = PlaidLinkRequest()
    let requestBody = try JSONEncoder().encode(linkTokenRequest)
    
    let linkResponse: PlaidLinkResponse = try await networkService.authenticatedRequest(
      endpoint: "/bank/link/create",
      method: .POST,
      body: requestBody,
      responseType: PlaidLinkResponse.self
    )
    
    // Debug: Print the response
    print("Plaid Link Response: \(linkResponse)")
    
    guard linkResponse.success else {
      throw PlaidError.linkTokenCreationFailed
    }
    
    linkToken = linkResponse.linkToken
  }
  
  func exchangePublicToken(_ publicToken: String) async throws {
    // In a real app, this would call your backend to exchange the public token
    // for an access token and fetch initial account data
    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
    
    // Simulate successful exchange
    print("Successfully exchanged public token: \(publicToken)")
  }
}
