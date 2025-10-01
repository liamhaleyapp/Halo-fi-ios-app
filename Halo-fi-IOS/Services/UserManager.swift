//
//  UserManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
import Foundation

// MARK: - User Manager
@Observable
class UserManager {
  var currentUser: User?
  var isAuthenticated = false
  var isLoading = false
  
  private let userDefaults = UserDefaults.standard
  private let userKey = "currentUser"
  
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
    isLoading = true
    
    // Simulate API call delay
    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
    
    // Create new user
    let newUser = User(
      email: email,
      firstName: firstName
    )
    
    // Save user locally (in real app, this would be API call)
    await MainActor.run {
      self.currentUser = newUser
      self.isAuthenticated = true
      self.isLoading = false
      self.saveUserToStorage()
    }
  }
  
  func signIn(email: String, password: String) async throws {
    isLoading = true
    
    // Simulate API call delay
    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
    
    // In real app, this would validate credentials with API
    // For now, we'll create a mock user if email contains "@"
    if email.contains("@") {
      let user = User(
        email: email,
        firstName: "User" // In real app, this would come from API
      )
      
      await MainActor.run {
        self.currentUser = user
        self.isAuthenticated = true
        self.isLoading = false
        self.saveUserToStorage()
      }
    } else {
      throw AuthError.invalidCredentials
    }
  }
  
  func signOut() {
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
      currentUser = user
      isAuthenticated = true
    }
  }
  
  private func clearUserFromStorage() {
    userDefaults.removeObject(forKey: userKey)
  }
}

