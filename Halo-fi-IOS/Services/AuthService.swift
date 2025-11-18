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
  func register(firstName: String, lastName: String, email: String, phone: String, password: String, dateOfBirth: Date) async throws {
    // Validate required fields
    if firstName.isEmpty || lastName.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty {
      throw AuthError.validationError([])
    }
    
    let registerRequest = SignupRequest(
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      password: password,
      dateOfBirth: formatDateForRequest(dateOfBirth)
    )
    
    let requestBody = try JSONEncoder().encode(registerRequest)
    
    let _: SignupResponse = try await networkService.publicRequest(
      endpoint: "/users/signup",
      method: .POST,
      body: requestBody,
      responseType: SignupResponse.self
    )
  }

  private func formatDateForRequest(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
  
  // MARK: - Refresh Token
  // TODO: Implement when refresh endpoint is available in the API
  // Currently not available in the API documentation
  func refreshToken(refreshToken: String) async throws -> LoginResponse {
    throw AuthError.serverError(501, "Token refresh not implemented") // Not implemented
  }
  
  // MARK: - Get User Profile
  func getUserProfile() async throws -> UserProfileResponse {
    do {
      let profileResponse: UserProfileResponse = try await networkService.authenticatedRequest(
        endpoint: "/auth/me",
        method: .GET,
        responseType: UserProfileResponse.self
      )
      
      return profileResponse
    } catch {
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
      let requestBody = try JSONEncoder().encode(request)
      
      let profileResponse: UserProfileResponse = try await networkService.authenticatedRequest(
        endpoint: "/auth/me",
        method: .PUT,
        body: requestBody,
        responseType: UserProfileResponse.self
      )
      
      return profileResponse
    } catch {
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
    throw AuthError.serverError(501, "Logout not implemented") // Not implemented
  }
}

