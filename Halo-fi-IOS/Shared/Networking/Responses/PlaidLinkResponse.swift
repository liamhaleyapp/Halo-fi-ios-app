//
//  PlaidLinkResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/16/25.
//

import Foundation

struct PlaidLinkResponse: Codable {
  let success: Bool
  let linkToken: String
  let expiresAt: String
  let message: String
  let error: String?
  
  enum CodingKeys: String, CodingKey {
    case success
    case linkToken = "link_token"
    case expiresAt = "expires_at"
    case message
    case error
  }
}
