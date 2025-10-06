//
//  UserManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

@Observable
class UserManager {
  var currentUser: User?
  var isAuthenticated = false
  var isLoading = false
  
  private let userDefaults = UserDefaults.standard
  private let userKey = "currentUser"
  private let tokenStorage = TokenStorage()
  private let authService = AuthService.shared
  
  init() {
    // Ensure we're on the main thread when setting @Published properties
    if Thread.isMainThread {
      loadUserFromStorage()
    } else {
      DispatchQueue.main.async {
        self.loadUserFromStorage()
      }
    }
  }
  
  // MARK: - Authentication Methods
  
  func signUp(email: String, password: String, firstName: String) async throws {
    print("🟡 UserManager: Starting signup process")
    isLoading = true
    
    do {
      print("🟡 UserManager: Calling AuthService.register")
      // For now, we'll use firstName as name and generate a placeholder phone
      // TODO: Add phone field to SignUpView when server requirements are clear
      try await authService.register(
        name: firstName,
        email: email,
        phone: "+1234567890", // Placeholder phone number
        password: password
      )
      
      print("✅ UserManager: Signup successful")
      // Signup successful - user will need to sign in separately
      await MainActor.run {
        self.isLoading = false
      }
    } catch {
      print("❌ UserManager: Signup failed with error: \(error)")
      print("❌ UserManager: Error type: \(type(of: error))")
      print("❌ UserManager: Error description: \(error.localizedDescription)")
      await MainActor.run {
        self.isLoading = false
      }
      throw error
    }
  }
  
  func signIn(email: String, password: String) async throws {
    isLoading = true
    
    do {
      let authResponse = try await authService.login(
        email: email,
        password: password
      )
      
      // Save tokens
      tokenStorage.saveTokens(
        accessToken: authResponse.accessToken,
        refreshToken: authResponse.refreshToken,
        expiresIn: authResponse.expiresIn
      )
      
      // Create user from API response
      let user = User(
        id: authResponse.authUser.authUserId,
        email: authResponse.authUser.email,
        firstName: "User" // We'll need to get this from the API response
      )
      
      await MainActor.run {
        self.currentUser = user
        self.isAuthenticated = true
        self.isLoading = false
        self.saveUserToStorage()
      }
    } catch {
      await MainActor.run {
        self.isLoading = false
      }
      throw error
    }
  }
  
  func signOut() {
    // TODO: Clear tokens from server when logout endpoint is available
    // For now, just clear local storage
    
    // Clear local storage
    tokenStorage.clearTokens()
    
    // Ensure we're on the main thread when setting @Published properties
    if Thread.isMainThread {
      currentUser = nil
      isAuthenticated = false
      clearUserFromStorage()
    } else {
      DispatchQueue.main.async {
        self.currentUser = nil
        self.isAuthenticated = false
        self.clearUserFromStorage()
      }
    }
  }
  
  func resetPassword(email: String) async throws {
    isLoading = true
    
    // Simulate API call delay
    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
    
    // In real app, this would send reset email
    await MainActor.run {
      self.isLoading = false
    }
  }
  
  // MARK: - User Onboarding
  
  func completeOnboarding() {
    // Ensure we're on the main thread when setting @Published properties
    if Thread.isMainThread {
      guard var user = currentUser else { return }
      user.isOnboarded = true
      currentUser = user
      saveUserToStorage()
    } else {
      DispatchQueue.main.async {
        self.completeOnboarding()
      }
    }
  }
  
  // MARK: - Storage Methods
  
  private func saveUserToStorage() {
    if let encoded = try? JSONEncoder().encode(currentUser) {
      userDefaults.set(encoded, forKey: userKey)
    }
  }
  
  private func loadUserFromStorage() {
    if let data = userDefaults.data(forKey: userKey),
       let user = try? JSONDecoder().decode(User.self, from: data) {
      
      // Check if we have valid tokens
      if tokenStorage.isTokenValid() {
        currentUser = user
        isAuthenticated = true
      } else {
        // Try to refresh token
        if let refreshToken = tokenStorage.getRefreshToken() {
          Task {
            await refreshTokensIfNeeded(refreshToken: refreshToken)
          }
        } else {
          // No valid tokens, clear user data
          clearUserFromStorage()
          tokenStorage.clearTokens()
        }
      }
    }
  }
  
  private func clearUserFromStorage() {
    userDefaults.removeObject(forKey: userKey)
  }
  
  // MARK: - Token Management
  
  private func refreshTokensIfNeeded(refreshToken: String) async {
    // TODO: Implement when refresh token endpoint is available
    // For now, if tokens are expired, sign out user
    await MainActor.run {
      self.signOut()
    }
  }
}

