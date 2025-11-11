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
  
  func signUp(firstName: String, lastName: String, phone: String, email: String, password: String, dateOfBirth: Date) async throws {
    isLoading = true
    
    do {
      try await authService.register(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        password: password,
        dateOfBirth: dateOfBirth
      )
      
      // After successful signup, the user will be fully populated after they sign in
      await MainActor.run {
        // Don't set as authenticated yet, wait for sign in
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.isLoading = false
      }
      throw error
    }
  }
  
  func signIn(phoneNumber: String, password: String) async throws {
    isLoading = true
    
    do {
      let authResponse = try await authService.login(
        phoneNumber: phoneNumber,
        password: password
      )
      
      // Save tokens using exact server expiration timestamp
      tokenStorage.saveTokensWithExpiration(
        accessToken: authResponse.authData.session.accessToken,
        refreshToken: authResponse.authData.session.refreshToken,
        expiresAt: authResponse.authData.session.expiresAt
      )
      
      // Create user from API response
      let authUser = authResponse.authData.authUser
      
      let trimmedDisplayName = authUser.appMetaData.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      
      let rawFirstName = authUser.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
      let sanitizedFirstName: String
      if let first = rawFirstName, !first.isEmpty {
        sanitizedFirstName = first
      } else if !trimmedDisplayName.isEmpty {
        sanitizedFirstName = trimmedDisplayName.components(separatedBy: " ").first ?? trimmedDisplayName
      } else {
        sanitizedFirstName = "User"
      }
      
      var sanitizedLastName: String?
      if let last = authUser.lastName?.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty {
        sanitizedLastName = last
      } else {
        let nameComponents = trimmedDisplayName.components(separatedBy: " ")
        if nameComponents.count > 1 {
          let joined = nameComponents.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
          if !joined.isEmpty {
            sanitizedLastName = joined
          }
        }
      }
      
      let trimmedPhone = authUser.phone.trimmingCharacters(in: .whitespacesAndNewlines)
      let sanitizedPhone = trimmedPhone.isEmpty ? nil : trimmedPhone
      let parsedDateOfBirth = parseDate(authUser.dateOfBirth)
      
      let user = User(
        id: authUser.authUserId,
        email: authUser.email,
        firstName: sanitizedFirstName,
        lastName: sanitizedLastName,
        phone: sanitizedPhone,
        dateOfBirth: parsedDateOfBirth
      )
      
      await MainActor.run {
        self.currentUser = user
        self.isAuthenticated = true
        self.isLoading = false
        self.saveUserToStorage()
      }
      
      // Fetch full profile data from server after login
      // This will update the user with any additional fields from /auth/me
      Task {
        try? await fetchUserProfile()
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
  
  // MARK: - User Profile Management
  
  /// Fetches the complete user profile from the server
  func fetchUserProfile() async throws {
    isLoading = true
    
    do {
      let profileResponse = try await authService.getUserProfile()
      
      // Debug: Print raw response
      print("🔍 /auth/me Response:")
      print("   Success: \(profileResponse.success)")
      print("   Message: \(profileResponse.message ?? "nil")")
      
      guard let wrapper = profileResponse.data else {
        print("⚠️ /auth/me: No user data in response")
        throw AuthError.networkError
      }
      
      let profileData = wrapper.user
      
      await MainActor.run {
        self.applyProfileData(
          profileData,
          overrideFirstName: nil,
          overrideLastName: nil,
          overridePhone: nil,
          overrideDateOfBirth: nil
        )
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.isLoading = false
      }
      throw error
    }
  }
  
  /// Helper method to parse date strings in various formats
  private func parseDate(_ dateString: String?) -> Date? {
    guard let dateString = dateString else { return nil }
    
    // Try ISO8601 formatters first
    let iso8601FormatterWithFractional = ISO8601DateFormatter()
    iso8601FormatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    
    let iso8601Formatter = ISO8601DateFormatter()
    iso8601Formatter.formatOptions = [.withInternetDateTime]
    
    let formatters: [DateFormatter?] = [
      // ISO 8601 formatters
      nil, // Placeholder for iso8601FormatterWithFractional
      nil, // Placeholder for iso8601Formatter
      // Custom formatters for common date formats
      createDateFormatter(format: "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"),
      createDateFormatter(format: "yyyy-MM-dd'T'HH:mm:ssZ"),
      createDateFormatter(format: "yyyy-MM-dd"),
      createDateFormatter(format: "yyyy/MM/dd")
    ]
    
    // Try ISO8601 formatters first
    if let date = iso8601FormatterWithFractional.date(from: dateString) {
      return date
    }
    if let date = iso8601Formatter.date(from: dateString) {
      return date
    }
    
    // Try custom formatters
    for formatter in formatters.compactMap({ $0 }) {
      if let date = formatter.date(from: dateString) {
        return date
      }
    }
    
    return nil
  }
  
  private func createDateFormatter(format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }
  
  private func formatDateForRequest(_ date: Date?) -> String? {
    guard let date = date else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter.string(from: date)
  }
  
  private func applyProfileData(
    _ profileData: UserProfileData,
    overrideFirstName: String?,
    overrideLastName: String?,
    overridePhone: String?,
    overrideDateOfBirth: Date?
  ) {
    // Debug: Print all profile data fields
    print("📋 Profile Data:")
    print("   ID: \(profileData.id)")
    print("   Email: \(profileData.email)")
    print("   Phone: \(profileData.phone ?? "nil")")
    print("   First Name: \(profileData.firstName)")
    print("   Last Name: \(profileData.lastName ?? "nil")")
    print("   Status: \(profileData.status ?? "nil")")
    print("   Date of Birth: \(profileData.dateOfBirth ?? "nil")")
    print("   Location: \(profileData.location ?? "nil")")
    
    let resolvedFirstName = (overrideFirstName ?? profileData.firstName).trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedLastName = overrideLastName ?? profileData.lastName
    let sanitizedLastName = (resolvedLastName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? nil : resolvedLastName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedPhone = (overridePhone ?? profileData.phone)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedDateOfBirth = overrideDateOfBirth ?? parseDate(profileData.dateOfBirth) ?? currentUser?.dateOfBirth
    
    let updatedUser = User(
      id: profileData.id,
      email: profileData.email,
      firstName: resolvedFirstName,
      lastName: sanitizedLastName,
      phone: resolvedPhone,
      dateOfBirth: resolvedDateOfBirth,
      createdAt: currentUser?.createdAt ?? Date(),
      isOnboarded: currentUser?.isOnboarded ?? false
    )
    
    currentUser = updatedUser
    saveUserToStorage()
  }
  
  func updateUserProfile(
    firstName: String? = nil,
    lastName: String? = nil,
    email: String? = nil,
    phone: String? = nil,
    dateOfBirth: Date? = nil
  ) async throws {
    guard currentUser != nil else {
      throw AuthError.networkError
    }
    
    let sanitizedFirstName = firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let sanitizedLastName = lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let sanitizedPhone = phone?.trimmingCharacters(in: .whitespacesAndNewlines)
    let sanitizedDateOfBirth = dateOfBirth
    
    let request = UpdateUserProfileRequest(
      firstName: sanitizedFirstName,
      lastName: sanitizedLastName?.isEmpty == true ? nil : sanitizedLastName,
      status: nil,
      parents: nil,
      motivations: nil,
      referralCode: nil,
      dateOfBirth: formatDateForRequest(sanitizedDateOfBirth),
      location: nil,
      maritalStatus: nil,
      dependent: nil,
      householdSize: nil,
      phone: sanitizedPhone?.isEmpty == true ? nil : sanitizedPhone
    )
    
    let response = try await authService.updateUserProfile(request: request)
    
    guard let wrapper = response.data else {
      throw AuthError.serverError(500)
    }
    
    let profileData = wrapper.user
    
    await MainActor.run {
      self.applyProfileData(
        profileData,
        overrideFirstName: sanitizedFirstName,
        overrideLastName: sanitizedLastName,
        overridePhone: sanitizedPhone,
        overrideDateOfBirth: sanitizedDateOfBirth
      )
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

