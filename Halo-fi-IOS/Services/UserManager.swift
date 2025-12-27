//
//  UserManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
import RevenueCat

@Observable
@MainActor
final class UserManager {
    var currentUser: User?
    var isAuthenticated = false
    var isLoading = false

    private let userDefaults = UserDefaults.standard
    private let userKey = "currentUser"
    private let onboardingKey = "user_onboarding_completed"
    private let tokenStorage: TokenStorageProtocol
    private let authService: AuthServiceProtocol

    /// Bank data manager - set via DI container after initialization
    private var bankDataManager: BankDataManager?

    // Onboarding state persisted independently of User object
    // This ensures onboarding status persists even when User object is refreshed from server
    var isOnboarded: Bool = false {
        didSet {
            userDefaults.set(isOnboarded, forKey: onboardingKey)

            if var user = currentUser {
                user.isOnboarded = isOnboarded
                currentUser = user
                saveUserToStorage()
            }
        }
    }

    init(tokenStorage: TokenStorageProtocol = TokenStorage(), authService: AuthServiceProtocol = AuthService.shared) {
        self.tokenStorage = tokenStorage
        self.authService = authService
        loadUserFromStorage()
        restoreOnboardingState()
    }

    /// Sets the bank data manager dependency (called from DIContainer after initialization)
    func setBankDataManager(_ manager: BankDataManager) {
        self.bankDataManager = manager
        // If user is already authenticated, configure bank data manager immediately
        if let user = currentUser, isAuthenticated {
            manager.configureForUser(userId: user.id)
        }
    }

    private func restoreOnboardingState() {
        if userDefaults.object(forKey: onboardingKey) != nil {
            isOnboarded = userDefaults.bool(forKey: onboardingKey)
        } else {
            isOnboarded = currentUser?.isOnboarded ?? false
        }
    }

    // MARK: - Authentication Methods

    func signUp(
        firstName: String,
        lastName: String,
        phone: String,
        email: String,
        password: String,
        dateOfBirth: Date
    ) async throws {
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
            isLoading = false
        } catch {
            isLoading = false
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

            tokenStorage.saveTokensWithExpiration(
                accessToken: authResponse.session.accessToken,
                refreshToken: authResponse.session.refreshToken,
                expiresAt: authResponse.session.expiresAt
            )

            Logger.debug("Token expires at: \(authResponse.session.expirationDate), duration: \(formatTokenDuration(authResponse.session.expiresIn))")

            let user = createUser(from: authResponse.authUser)
            applySignInState(user: user)

            do {
                _ = try await Purchases.shared.logIn(user.id)
            } catch {
                Logger.warning("RevenueCat login failed: \(error.localizedDescription)")
            }

            Task {
                try? await fetchUserProfile()
            }
        } catch {
            isLoading = false
            throw error
        }
    }

    func signOut() {
        // Clear bank data first (before clearing user)
        bankDataManager?.clearAllData()

        tokenStorage.clearTokens()

        Task {
            do {
                _ = try await Purchases.shared.logOut()
            } catch {
                Logger.warning("RevenueCat logout failed: \(error.localizedDescription)")
            }
        }

        currentUser = nil
        isAuthenticated = false
        clearUserFromStorage()
        // Note: We intentionally DON'T clear onboarding status on sign out
        // so users don't have to re-onboard if they sign back in
    }

    func resetPassword(email: String) async throws {
        throw AuthError.notImplemented
    }

    // MARK: - User Onboarding

    func completeOnboarding() {
        isOnboarded = true
    }

    /// Resets onboarding status to false (for testing/debugging purposes)
    func resetOnboarding() {
        isOnboarded = false
    }

    /// Checks if user has completed onboarding by checking persisted state or bank accounts
    func checkOnboardingStatus(bankDataManager: BankDataManager? = nil) async {
        if userDefaults.object(forKey: onboardingKey) != nil {
            return
        }

        guard let bankDataManager = bankDataManager else { return }

        do {
            try await bankDataManager.fetchAccounts(forceRefresh: false)
            let hasAccounts = bankDataManager.accounts?.isEmpty == false
            if hasAccounts {
                isOnboarded = true
            }
        } catch {
            // If we can't fetch accounts, don't change onboarding status
        }
    }

    // MARK: - User Profile Management

    func fetchUserProfile() async throws {
        isLoading = true

        do {
            let profileResponse = try await authService.getUserProfile()

            guard let wrapper = profileResponse.data else {
                isLoading = false
                throw AuthError.invalidResponse
            }

            applyProfileData(
                wrapper.user,
                overrideFirstName: nil,
                overrideLastName: nil,
                overridePhone: nil,
                overrideDateOfBirth: nil
            )
            isLoading = false
        } catch {
            isLoading = false
            throw error
        }
    }

    func updateUserProfile(
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        dateOfBirth: Date? = nil
    ) async throws {
        guard currentUser != nil else {
            throw AuthError.notAuthenticated
        }

        let sanitizedFirstName = firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedLastName = lastName?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Normalize phone using USPhoneFormatting (same as sign-in/sign-up)
        let sanitizedPhone: String?
        if let phone = phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sanitizedPhone = USPhoneFormatting.formatForAPI(phone)
        } else {
            sanitizedPhone = nil
        }

        let request = UpdateUserProfileRequest(
            firstName: sanitizedFirstName,
            lastName: sanitizedLastName?.isEmpty == true ? nil : sanitizedLastName,
            status: nil,
            parents: nil,
            motivations: nil,
            referralCode: nil,
            dateOfBirth: DateFormatting.formatForAPI(dateOfBirth),
            location: nil,
            maritalStatus: nil,
            dependent: nil,
            householdSize: nil,
            phone: sanitizedPhone?.isEmpty == true ? nil : sanitizedPhone
        )

        let response = try await authService.updateUserProfile(request: request)

        guard let wrapper = response.data else {
            throw AuthError.invalidResponse
        }

        applyProfileData(
            wrapper.user,
            overrideFirstName: sanitizedFirstName,
            overrideLastName: sanitizedLastName,
            overridePhone: sanitizedPhone,
            overrideDateOfBirth: dateOfBirth
        )
    }

    // MARK: - Private Helpers

    private func createUser(from authUser: AuthUser) -> User {
        let trimmedDisplayName = authUser.appMetaData.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        let sanitizedFirstName: String
        if let first = authUser.firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
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
        let parsedDateOfBirth = authUser.dateOfBirth.flatMap { DateFormatting.parse($0) }

        return User(
            id: authUser.authUserId,
            email: authUser.email,
            firstName: sanitizedFirstName,
            lastName: sanitizedLastName,
            phone: sanitizedPhone,
            dateOfBirth: parsedDateOfBirth
        )
    }

    private func applySignInState(user: User) {
        let hasExplicitOnboardingStatus = userDefaults.object(forKey: onboardingKey) != nil
        let storedOnboardingValue = userDefaults.bool(forKey: onboardingKey)

        // Check both in-memory user AND persisted user to detect different users
        // This handles app reinstall where Keychain tokens are cleared but UserDefaults persist
        let previousUserId: String?
        if let currentUser = currentUser {
            previousUserId = currentUser.id
        } else if let data = userDefaults.data(forKey: userKey),
                  let persistedUser = try? JSONDecoder().decode(User.self, from: data) {
            previousUserId = persistedUser.id
        } else {
            previousUserId = nil
        }

        // Only trust stored onboarding status if we can VERIFY it's the same user
        // previousUserId must be non-nil AND match the new user's ID
        let isSameUser = previousUserId != nil && previousUserId == user.id

        Logger.info("UserManager.applySignInState: newUserId=\(user.id), previousUserId=\(previousUserId ?? "nil"), isSameUser=\(isSameUser), hasExplicitOnboardingStatus=\(hasExplicitOnboardingStatus), storedOnboardingValue=\(storedOnboardingValue)")

        let preservedOnboardingStatus: Bool
        if hasExplicitOnboardingStatus && isSameUser {
            // Same user returning - trust persisted status
            preservedOnboardingStatus = userDefaults.bool(forKey: onboardingKey)
            Logger.info("UserManager.applySignInState: Same user path - preservedOnboardingStatus=\(preservedOnboardingStatus)")
        } else {
            // Different user, unknown user, or fresh install - reset onboarding
            preservedOnboardingStatus = false
            userDefaults.set(false, forKey: onboardingKey)
            Logger.info("UserManager.applySignInState: New/different user path - reset to false")
        }

        var newUser = user
        newUser.isOnboarded = preservedOnboardingStatus
        currentUser = newUser
        isAuthenticated = true
        isLoading = false

        // IMPORTANT: Update the UserManager's isOnboarded property (what MainTabView checks)
        // Setting this also persists to UserDefaults via didSet
        isOnboarded = preservedOnboardingStatus
        Logger.info("UserManager.applySignInState: Final isOnboarded=\(isOnboarded)")

        saveUserToStorage()

        // Configure bank data manager for this user
        bankDataManager?.configureForUser(userId: user.id)
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
        let sanitizedLastName = (resolvedLastName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            ? nil
            : resolvedLastName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPhone = (overridePhone ?? profileData.phone)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDateOfBirth = overrideDateOfBirth
            ?? profileData.dateOfBirth.flatMap { DateFormatting.parse($0) }
            ?? currentUser?.dateOfBirth

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

    private func formatTokenDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours >= 1 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    // MARK: - Storage Methods

    private func saveUserToStorage() {
        if let encoded = try? JSONEncoder().encode(currentUser) {
            userDefaults.set(encoded, forKey: userKey)
        }
    }

    private func loadUserFromStorage() {
        guard let data = userDefaults.data(forKey: userKey),
              let user = try? JSONDecoder().decode(User.self, from: data) else {
            return
        }

        if tokenStorage.isTokenValid() {
            currentUser = user
            isAuthenticated = true
        } else if let refreshToken = tokenStorage.getRefreshToken() {
            Task {
                await refreshTokensIfNeeded(refreshToken: refreshToken)
            }
        } else {
            clearUserFromStorage()
            tokenStorage.clearTokens()
        }
    }

    private func clearUserFromStorage() {
        userDefaults.removeObject(forKey: userKey)
    }

    // MARK: - Token Management

    private func refreshTokensIfNeeded(refreshToken: String) async {
        // TODO: Implement when refresh token endpoint is available
        signOut()
    }
}
