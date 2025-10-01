//
//  PlaidManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

class PlaidManager: ObservableObject {
  @Published var linkToken: String = ""
  
  func createLinkToken() async throws {
    // In a real app, this would call your backend
    // For now, we'll simulate it
    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
    
    // Simulate getting a link token from your backend
    linkToken = "link-sandbox-\(UUID().uuidString)"
  }
  
  func exchangePublicToken(_ publicToken: String) async throws {
    // In a real app, this would call your backend to exchange the public token
    // for an access token and fetch initial account data
    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
    
    // Simulate successful exchange
    print("Successfully exchanged public token: \(publicToken)")
  }
}
