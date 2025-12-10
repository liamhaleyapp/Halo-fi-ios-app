//
//  UserManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
import RevenueCat

@Observable
class UserManager {
  var currentUser: User?
  var isAuthenticated = false
  var isLoading = false
  
  private let userDefaults = UserDefaults.standard
  private let userKey = "currentUser"
  private let onboardingKey = "user_onboarding_completed"
  private let tokenStorage = TokenStorage()
  private let authService = AuthService.shared
  
  // Onboarding state persisted independently of User object
  // This ensures onboarding status persists even when User object is refreshed from server
  var isOnboarded: Bool = false {
    didSet {
      // Persist to UserDefaults
      userDefaults.set(isOnboarded, forKey: onboardingKey)
      
      // Keep currentUser in sync
      if var user = currentUser {
        user.isOnboarded = isOnboarded
        currentUser = user
        saveUserToStorage()
      }
    }
  }
  
  init() {
    // Ensure we're on the main thread when setting @Published properties
    if Thread.isMainThread {
      loadUserFromStorage()
      restoreOnboardingState()
    } else {
      DispatchQueue.main.async {
        self.loadUserFromStorage()
        self.restoreOnboardingState()
      }
    }
  }
  
  private func restoreOnboardingState() {
    if userDefaults.object(forKey: onboardingKey) != nil {
      // Explicit persisted value wins
      isOnboarded = userDefaults.bool(forKey: onboardingKey)
    } else {
      // Fallback to user object if needed
      isOnboarded = currentUser?.isOnboarded ?? false
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
        accessToken: authResponse.session.accessToken,
        refreshToken: authResponse.session.refreshToken,
        expiresAt: authResponse.session.expiresAt
      )
      
      // Print token expiration for debugging
      let expirationDate = authResponse.session.expirationDate
      let formatter = DateFormatter()
      formatter.dateStyle = .medium
      formatter.timeStyle = .medium
      formatter.timeZone = TimeZone.current
      let expiresInSeconds = authResponse.session.expiresIn
      let expiresInMinutes = expiresInSeconds / 60
      let expiresInHours = expiresInMinutes / 60
      let durationString: String
      if expiresInHours >= 1 {
        let remainingMinutes = expiresInMinutes % 60
        durationString = remainingMinutes > 0 ? "\(expiresInHours)h \(remainingMinutes)m" : "\(expiresInHours)h"
      } else {
        durationString = "\(expiresInMinutes)m"
      }
      print("🔐 Token expiration: \(authResponse.session.expiresAt) (Unix timestamp)")
      print("🔐 Token expires at: \(formatter.string(from: expirationDate))")
      print("🔐 Token duration: \(expiresInSeconds)s (\(durationString))")
      
      // Create user from API response
      let authUser = authResponse.authUser
      
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
        // Check if this is a new user (different user ID) or if onboarding status hasn't been explicitly set
        let isNewUser = currentUser?.id != user.id
        let hasExplicitOnboardingStatus = userDefaults.object(forKey: onboardingKey) != nil
        
        // For new users or when onboarding status isn't explicitly set, default to false
        // Only preserve onboarding status if it's the same user and status is explicitly set
        let preservedOnboardingStatus: Bool
        if isNewUser || !hasExplicitOnboardingStatus {
          // New user or no explicit status - ensure onboarding is false
          preservedOnboardingStatus = false
          // Explicitly set it to false in UserDefaults
          userDefaults.set(false, forKey: onboardingKey)
        } else {
          // Same user with explicit status - preserve it
          preservedOnboardingStatus = isOnboarded
        }
        
        var newUser = user
        newUser.isOnboarded = preservedOnboardingStatus
        self.currentUser = newUser
        self.isAuthenticated = true
        self.isLoading = false
        self.saveUserToStorage()
      }
      
      // Identify RevenueCat user with Supabase user ID
      // This ties RevenueCat subscriptions to the user account, allowing subscriptions
      // to follow the user across devices
      do {
        _ = try await Purchases.shared.logIn(user.id)
      } catch {
        // Log error but don't fail sign in if RevenueCat identification fails
        // RevenueCat identification failure is non-critical
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
    
    // Log out from RevenueCat to clear subscription state
    // This ensures subscriptions don't persist across different user accounts
    Task {
      do {
        _ = try await Purchases.shared.logOut()
      } catch {
        // RevenueCat logout failure is non-critical
      }
    }
    
    // Ensure we're on the main thread when setting properties
    if Thread.isMainThread {
      currentUser = nil
      isAuthenticated = false
      clearUserFromStorage()
      // Note: We intentionally DON'T clear onboarding status on sign out
      // so users don't have to re-onboard if they sign back in
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
    if Thread.isMainThread {
      isOnboarded = true
    } else {
      DispatchQueue.main.async {
        self.isOnboarded = true
      }
    }
  }
  
  /// Resets onboarding status to false (for testing/debugging purposes)
  func resetOnboarding() {
    if Thread.isMainThread {
      isOnboarded = false
    } else {
      DispatchQueue.main.async {
        self.isOnboarded = false
      }
    }
  }
  
  /// Checks if user has completed onboarding by checking persisted state or bank accounts
  /// - Parameter bankDataManager: Optional BankDataManager to check for connected accounts
  func checkOnboardingStatus(bankDataManager: BankDataManager? = nil) async {
    // If we already have onboarding status persisted, use it
    if userDefaults.object(forKey: onboardingKey) != nil {
      return
    }
    
    // Fallback: Check if user has connected bank accounts (indicates onboarding completion)
    if let bankDataManager = bankDataManager {
      do {
        try await bankDataManager.fetchAccounts(forceRefresh: false)
        // Access main actor-isolated property on main actor
        let hasAccounts = await MainActor.run {
          guard let accounts = bankDataManager.accounts else { return false }
          return !accounts.isEmpty
        }
        
        if hasAccounts {
          await MainActor.run {
            self.isOnboarded = true
          }
        }
      } catch {
        // If we can't fetch accounts, don't change onboarding status
      }
    }
  }
  
  // MARK: - User Profile Management
  
  /// Fetches the complete user profile from the server
  func fetchUserProfile() async throws {
    isLoading = true
    
    do {
      let profileResponse = try await authService.getUserProfile()
      
      guard let wrapper = profileResponse.data else {
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
    let resolvedFirstName = (overrideFirstName ?? profileData.firstName).trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedLastName = overrideLastName ?? profileData.lastName
    let sanitizedLastName = (resolvedLastName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? nil : resolvedLastName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedPhone = (overridePhone ?? profileData.phone)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedDateOfBirth = overrideDateOfBirth ?? parseDate(profileData.dateOfBirth) ?? currentUser?.dateOfBirth
    
    // Preserve onboarding state from persisted storage (not from User object)
    // This ensures onboarding status persists across profile refreshes
    let preservedOnboardingStatus = isOnboarded
    
    let updatedUser = User(
      id: profileData.id,
      email: profileData.email,
      firstName: resolvedFirstName,
      lastName: sanitizedLastName,
      phone: resolvedPhone,
      dateOfBirth: resolvedDateOfBirth,
      createdAt: currentUser?.createdAt ?? Date(),
      isOnboarded: preservedOnboardingStatus
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
      throw AuthError.serverError(500, "Invalid response from server")
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
