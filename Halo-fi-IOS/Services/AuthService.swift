//
//  AuthService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Authentication Service
class AuthService {
  static let shared = AuthService()
  
  private let networkService = NetworkService.shared
  
  private init() {}
  
  // MARK: - Login
  func login(phoneNumber: String, password: String) async throws -> LoginResponse {
    let loginRequest = LoginRequest(
      phone: phoneNumber,
      password: password
    )
    
    let requestBody = try JSONEncoder().encode(loginRequest)
    
    do {
      let authResponse: LoginResponse = try await networkService.publicRequest(
        endpoint: "/auth/login",
        method: .POST,
        body: requestBody,
        responseType: LoginResponse.self
      )
      return authResponse
    } catch {
      // NetworkService handles basic errors, but we need to handle auth-specific errors
      if let authError = error as? AuthError {
        throw authError
      } else {
        throw AuthError.networkError
      }
    }
  }
  
  // MARK: - Register
  func register(firstName: String, lastName: String, email: String, phone: String, password: String) async throws {
    // Validate required fields
    if firstName.isEmpty || lastName.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty {
      throw AuthError.validationError([])
    }
    
    let registerRequest = SignupRequest(
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      password: password
    )
    
    let requestBody = try JSONEncoder().encode(registerRequest)
    
    let _: SignupResponse = try await networkService.publicRequest(
      endpoint: "/users/signup",
      method: .POST,
      body: requestBody,
      responseType: SignupResponse.self
    )
  }
  
  // MARK: - Refresh Token
  // TODO: Implement when refresh endpoint is available in the API
  // Currently not available in the API documentation
  func refreshToken(refreshToken: String) async throws -> LoginResponse {
    throw AuthError.serverError(501) // Not implemented
  }
  
  // MARK: - Get User Profile
  func getUserProfile() async throws -> UserProfileResponse {
    do {
      // Debug: Print endpoint being called
      print("🌐 Calling /auth/me endpoint...")
      
      let profileResponse: UserProfileResponse = try await networkService.authenticatedRequest(
        endpoint: "/auth/me",
        method: .GET,
        responseType: UserProfileResponse.self
      )
      
      // Debug: Print raw JSON if we can decode it
      if let jsonData = try? JSONEncoder().encode(profileResponse),
         let jsonString = String(data: jsonData, encoding: .utf8) {
        print("📦 /auth/me Raw JSON Response:")
        print(jsonString)
      }
      
      return profileResponse
    } catch {
      print("❌ /auth/me Error: \(error)")
      // NetworkService handles basic errors, but we need to handle auth-specific errors
      if let authError = error as? AuthError {
        throw authError
      } else {
        throw AuthError.networkError
      }
    }
  }
  
  // MARK: - Update User Profile
  func updateUserProfile(request: UpdateUserProfileRequest) async throws -> UserProfileResponse {
    do {
      print("📝 Updating /auth/me profile...")
      let requestBody = try JSONEncoder().encode(request)
      
      let profileResponse: UserProfileResponse = try await networkService.authenticatedRequest(
        endpoint: "/auth/me",
        method: .PUT,
        body: requestBody,
        responseType: UserProfileResponse.self
      )
      
      if let jsonData = try? JSONEncoder().encode(profileResponse),
         let jsonString = String(data: jsonData, encoding: .utf8) {
        print("✅ /auth/me Update Response:")
        print(jsonString)
      }
      
      return profileResponse
    } catch {
      print("❌ /auth/me Update Error: \(error)")
      if let authError = error as? AuthError {
        throw authError
      } else {
        throw AuthError.networkError
      }
    }
  }
  
  // MARK: - Logout
  // TODO: Implement when logout endpoint is available in the API
  // Currently not available in the API documentation
  func logout(accessToken: String) async throws {
    // For now, just clear local tokens
    // Server-side logout not available yet
    throw AuthError.serverError(501) // Not implemented
  }
}

