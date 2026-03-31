//
//  AuthResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/13/25.
//
import Foundation

struct LoginResponse: Codable {
  let success: Bool
  let message: String?
  let error: String?
  let authUser: AuthUser?
  let session: AuthSession?

  enum CodingKeys: String, CodingKey {
    case success
    case message
    case error
    case authUser = "auth_user"
    case session
  }
}

struct AuthUser: Codable {
  let authUserId: String
  let firstName: String?
  let lastName: String?
  let email: String
  let phone: String
  let dateOfBirth: String?
  let emailConfirmed: Bool
  let phoneConfirmed: Bool
  let createdAt: String
  let appMetaData: AppMetaData
  let userMetaData: [String: AnyCodable]?
  
  enum CodingKeys: String, CodingKey {
    case authUserId = "id"
    case firstName = "first_name"
    case lastName = "last_name"
    case email
    case phone
    case dateOfBirth = "date_of_birth"
    case emailConfirmed = "email_confirmed"
    case phoneConfirmed = "phone_confirmed"
    case createdAt = "created_at"
    case appMetaData = "app_metadata"
    case userMetaData = "user_metadata"
  }
}

struct AppMetaData: Codable {
  let displayName: String
  let provider: String
  let providers: [String]
  
  enum CodingKeys: String, CodingKey {
    case displayName = "display_name"
    case provider
    case providers
  }
}

struct AuthSession: Codable {
  let accessToken: String
  let refreshToken: String
  let expiresAt: Int
  let expiresIn: Int
  
  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresAt = "expires_at"
    case expiresIn = "expires_in"
  }
  
  var expirationDate: Date {
    Date(timeIntervalSince1970: TimeInterval(expiresAt))
  }
  
  var isExpired: Bool {
    Date() >= expirationDate
  }
}
