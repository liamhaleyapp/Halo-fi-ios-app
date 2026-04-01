//
//  UserManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
import RevenueCat

extension Notification.Name {
    static let bankDataConfigurationComplete = Notification.Name("bankDataConfigurationComplete")
}

@Observable
@MainActor
final class UserManager {
    var currentUser: User?
    var isAuthenticated = false
    var isLoading = false

    /// Whether we're still determining the user's destination after login
    /// While true, show a splash screen. When false, show main app or onboarding based on isOnboarded.
    var isResolvingDestination = false

    private let userDefaults = UserDefaults.standard
    private let userKey = "currentUser"
    private let legacyOnboardingKey = "user_onboarding_completed"  // Legacy global key for migration
    private let tokenStorage: TokenStorageProtocol
    private let authService: AuthServiceProtocol

    /// Returns the per-user onboarding key for the given user ID
    private func onboardingKey(for userId: String) -> String {
        "user_onboarding_completed_\(userId)"
    }

    /// Bank data manager - set via DI container after initialization
    private var bankDataManager: BankDataManager?

    // Onboarding state persisted independently of User object
    // This ensures onboarding status persists even when User object is refreshed from server
    // Uses per-user key: "user_onboarding_completed_{userId}"
    var isOnboarded: Bool = false {
        didSet {
            // Store per-user onboarding status
            if let userId = currentUser?.id {
                userDefaults.set(isOnboarded, forKey: onboardingKey(for: userId))
            }

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
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .bankDataConfigurationComplete,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let hasAccounts = notification.userInfo?["hasAccounts"] as? Bool ?? false
            Task { @MainActor in
                self.resolveDestination(hasAccounts: hasAccounts)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSessionExpired()
            }
        }
    }

    /// Called when NetworkService determines the session is no longer valid.
    private func handleSessionExpired() {
        Logger.warning("Session expired - signing out user")
        signOut()
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
        guard let userId = currentUser?.id else {
            isOnboarded = false
            return
        }

        let userOnboardingKey = onboardingKey(for: userId)
        if userDefaults.object(forKey: userOnboardingKey) != nil {
            isOnboarded = userDefaults.bool(forKey: userOnboardingKey)
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

            guard let session = authResponse.session,
                  let authUser = authResponse.authUser else {
                throw AuthError.invalidResponse
            }

            tokenStorage.saveTokensWithExpiration(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                expiresAt: session.expiresAt
            )

            Logger.debug("Token expires at: \(session.expirationDate), duration: \(formatTokenDuration(session.expiresIn))")

            let user = createUser(from: authUser)
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

    func socialSignIn(provider: String, idToken: String, nonce: String? = nil) async throws {
        isLoading = true

        do {
            let authResponse = try await authService.socialLogin(
                provider: provider,
                idToken: idToken,
                nonce: nonce
            )

            guard let session = authResponse.session,
                  let authUser = authResponse.authUser else {
                throw AuthError.invalidResponse
            }

            tokenStorage.saveTokensWithExpiration(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                expiresAt: session.expiresAt
            )

            let user = createUser(from: authUser)
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
        guard let userId = currentUser?.id else { return }

        let userOnboardingKey = onboardingKey(for: userId)
        if userDefaults.object(forKey: userOnboardingKey) != nil {
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
        // Don't determine onboarding status yet - wait for account data
        // This prevents race conditions and jarring transitions

        currentUser = user
        isAuthenticated = true
        isLoading = false
        isResolvingDestination = true  // Show splash while we fetch account data

        Logger.info("UserManager.applySignInState: userId=\(user.id), isResolvingDestination=true")

        saveUserToStorage()

        // Configure bank data manager - it will notify us when done via NotificationCenter
        bankDataManager?.configureForUser(userId: user.id)
    }

    /// Called after bank data is fetched to determine the user's destination
    /// Source of truth: if user has accounts, they've completed onboarding
    func resolveDestination(hasAccounts: Bool) {
        guard let userId = currentUser?.id else {
            isResolvingDestination = false
            return
        }

        let userOnboardingKey = onboardingKey(for: userId)

        if hasAccounts {
            // User has accounts = they've completed onboarding
            isOnboarded = true
            // Persist this for future reference
            userDefaults.set(true, forKey: userOnboardingKey)
            Logger.info("UserManager.resolveDestination: User has accounts, isOnboarded=true")
        } else {
            // No accounts - check stored status as fallback (for edge cases)
            if userDefaults.object(forKey: userOnboardingKey) != nil {
                let storedValue = userDefaults.bool(forKey: userOnboardingKey)
                isOnboarded = storedValue
                Logger.info("UserManager.resolveDestination: No accounts, using stored status=\(storedValue)")
            } else {
                // No accounts and no stored status = new user, show onboarding
                isOnboarded = false
                Logger.info("UserManager.resolveDestination: No accounts, no stored status, isOnboarded=false")
            }
        }

        isResolvingDestination = false
        Logger.info("UserManager.resolveDestination: Complete - isOnboarded=\(isOnboarded)")
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
        do {
            let response = try await authService.refreshToken(refreshToken: refreshToken)

            // Save new tokens
            tokenStorage.saveTokensWithExpiration(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiresAt: response.expiresAt
            )

            // Restore user from storage (user data doesn't change, just tokens)
            if let data = userDefaults.data(forKey: userKey),
               let user = try? JSONDecoder().decode(User.self, from: data) {
                currentUser = user
                isAuthenticated = true
                bankDataManager?.configureForUser(userId: user.id)
            }

            Logger.debug("Token refresh successful during app launch")
        } catch {
            Logger.error("Token refresh failed during app launch: \(error.localizedDescription)")
            signOut()
        }
    }
}
