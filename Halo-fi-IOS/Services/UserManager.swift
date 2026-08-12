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
    private let biometricCredentialStore: BiometricCredentialStoreProtocol

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

    init(
        tokenStorage: TokenStorageProtocol = TokenStorage(),
        authService: AuthServiceProtocol = AuthService.shared,
        biometricCredentialStore: BiometricCredentialStoreProtocol = BiometricCredentialStore()
    ) {
        self.tokenStorage = tokenStorage
        self.authService = authService
        self.biometricCredentialStore = biometricCredentialStore
        backfillFlagsFromKeychain()
        loadUserFromStorage()
        restoreOnboardingState()
        setupNotificationObservers()
    }

    /// iOS Keychain persists across app uninstall, but UserDefaults does not.
    /// If biometric creds survived a reinstall, treat the device as a returning
    /// user so SignInView skips the marketing carousel and the post-reinstall
    /// Face ID auto-prompt fires correctly.
    private func backfillFlagsFromKeychain() {
        if biometricCredentialStore.hasEnrolledCredentials {
            userDefaults.set(true, forKey: "has_signed_in_before")
            // Biometric creds use password+phone caching, so the user is a
            // password account by definition. Backfill the provider so the
            // sign-in screen tailors itself appropriately.
            if userDefaults.string(forKey: "last_auth_provider") == nil {
                userDefaults.set("password", forKey: "last_auth_provider")
            }
        }
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
        dateOfBirth: Date? = nil
    ) async throws -> SignupResponse {
        isLoading = true

        do {
            let response = try await authService.register(
                firstName: firstName,
                lastName: lastName,
                email: email,
                phone: phone,
                password: password,
                dateOfBirth: dateOfBirth
            )
            isLoading = false
            return response
        } catch {
            isLoading = false
            throw error
        }
    }

    /// Verify the phone OTP sent during signup. On success the user's
    /// phone is marked confirmed in Supabase; the caller can then sign
    /// in normally with phone + password.
    func verifyPhoneOTP(idUser: String, code: String) async throws {
        struct VerifyBody: Encodable {
            let idUser: String
            let verificationToken: String
            enum CodingKeys: String, CodingKey {
                case idUser = "id_user"
                case verificationToken = "verification_token"
            }
        }
        // Backend wraps verify_otp's response shape variably, so we just
        // check the HTTP status. A failed verify returns 400 from the
        // controller and is thrown by NetworkService as a serverError.
        struct VerifyResponse: Codable {}

        let body = try JSONEncoder().encode(VerifyBody(idUser: idUser, verificationToken: code))
        let _: VerifyResponse = try await NetworkService.shared.publicRequest(
            endpoint: APIEndpoints.Auth.verifyPhoneCode,
            method: .POST,
            body: body,
            responseType: VerifyResponse.self
        )
    }

    /// Trigger a fresh SMS OTP for an unverified user.
    func resendPhoneOTP(idUser: String) async throws {
        struct ResendBody: Encodable {
            let userAuthId: String
            enum CodingKeys: String, CodingKey {
                case userAuthId = "user_auth_id"
            }
        }
        struct ResendResponse: Codable {}

        let body = try JSONEncoder().encode(ResendBody(userAuthId: idUser))
        let _: ResendResponse = try await NetworkService.shared.publicRequest(
            endpoint: APIEndpoints.Auth.resendPhoneCode,
            method: .POST,
            body: body,
            responseType: ResendResponse.self
        )
    }

    func signIn(email: String, password: String) async throws {
        isLoading = true

        do {
            let authResponse = try await authService.login(
                email: email,
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

            // Remember the auth method so the sign-in screen can tailor itself
            // for returning users (auto Face ID for password, OAuth-only mode
            // for Apple/Google). Visually-impaired users especially benefit
            // from the smaller focusable surface this enables.
            userDefaults.set("password", forKey: "last_auth_provider")

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

    func socialSignIn(
        provider: String,
        idToken: String,
        nonce: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil
    ) async throws {
        isLoading = true

        do {
            let authResponse = try await authService.socialLogin(
                provider: provider,
                idToken: idToken,
                nonce: nonce,
                firstName: firstName,
                lastName: lastName
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

            // Remember which OAuth provider was used so SignInView can show
            // only that button on subsequent sign-ins.
            userDefaults.set(provider, forKey: "last_auth_provider")

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
        // Intentionally NOT clearing biometricCredentialStore — Face ID is
        // enrolled per-device so the user can sign back in quickly. The
        // explicit Settings toggle wipes it; account deletion does too.

        Task {
            do {
                _ = try await Purchases.shared.logOut()
            } catch {
                Logger.warning("RevenueCat logout failed: \(error.localizedDescription)")
            }
        }

        // Clear this user's local AI-consent mirror before dropping
        // currentUser (the key is derived from the user id). The server
        // remains the source of truth and re-hydrates on next sign-in;
        // this just guarantees no stale flag lingers on the device.
        if let grantedKey = aiConsentKey("granted") {
            userDefaults.removeObject(forKey: grantedKey)
        }
        if let versionKey = aiConsentKey("policy_version") {
            userDefaults.removeObject(forKey: versionKey)
        }

        currentUser = nil
        isAuthenticated = false
        clearUserFromStorage()
        // Note: We intentionally DON'T clear onboarding status on sign out
        // so users don't have to re-onboard if they sign back in
    }

    func resetPassword(email: String) async throws {
        struct ResetBody: Encodable {
            let email: String
        }
        struct ResetResponse: Codable {
            let success: Bool
            let message: String?
        }

        let body = try JSONEncoder().encode(ResetBody(email: email))
        let _: ResetResponse = try await NetworkService.shared.publicRequest(
            endpoint: APIEndpoints.Auth.resetPassword,
            method: .POST,
            body: body,
            responseType: ResetResponse.self
        )
    }

    /// SMS variant of password reset request. Triggers a 6-digit OTP
    /// to the user's phone via Supabase + Twilio. The flow afterwards
    /// is identical to the email path: verify → set new password.
    func resetPasswordSMS(phone: String) async throws {
        struct ResetBody: Encodable {
            let phone: String
        }
        struct ResetResponse: Codable {
            let success: Bool
            let message: String?
        }

        let body = try JSONEncoder().encode(ResetBody(phone: phone))
        let _: ResetResponse = try await NetworkService.shared.publicRequest(
            endpoint: APIEndpoints.Auth.resetPasswordSMS,
            method: .POST,
            body: body,
            responseType: ResetResponse.self
        )
    }

    /// SMS variant of OTP verification for password reset. Returns the
    /// short-lived recovery access_token that should be passed to
    /// setNewPassword.
    func verifyPasswordResetSMSOTP(phone: String, code: String) async throws -> String {
        struct VerifyBody: Encodable {
            let phone: String
            let token: String
        }
        struct VerifyResponse: Codable {
            let success: Bool
            let accessToken: String
            let refreshToken: String
            let tokenType: String
            let expiresIn: Int

            enum CodingKeys: String, CodingKey {
                case success
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case tokenType = "token_type"
                case expiresIn = "expires_in"
            }
        }

        let body = try JSONEncoder().encode(VerifyBody(phone: phone, token: code))
        let response: VerifyResponse = try await NetworkService.shared.publicRequest(
            endpoint: APIEndpoints.Auth.verifyResetSMSOTP,
            method: .POST,
            body: body,
            responseType: VerifyResponse.self
        )
        return response.accessToken
    }

    /// Step 2 of password reset. Submits the 6-digit code from the
    /// reset email; on success the backend returns a short-lived
    /// recovery access_token that must be passed to setNewPassword.
    func verifyPasswordResetOTP(email: String, code: String) async throws -> String {
        struct VerifyBody: Encodable {
            let email: String
            let token: String
        }
        struct VerifyResponse: Codable {
            let success: Bool
            let accessToken: String
            let refreshToken: String
            let tokenType: String
            let expiresIn: Int

            enum CodingKeys: String, CodingKey {
                case success
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case tokenType = "token_type"
                case expiresIn = "expires_in"
            }
        }

        let body = try JSONEncoder().encode(VerifyBody(email: email, token: code))
        let response: VerifyResponse = try await NetworkService.shared.publicRequest(
            endpoint: APIEndpoints.Auth.verifyResetOTP,
            method: .POST,
            body: body,
            responseType: VerifyResponse.self
        )
        return response.accessToken
    }

    /// Step 3 of password reset. Sets the new password using the
    /// recovery access_token from verifyPasswordResetOTP. Made out-of-band
    /// of NetworkService because the recovery token isn't stored in
    /// TokenStorage — it's a one-shot credential for this flow only.
    func setNewPassword(recoveryAccessToken: String, newPassword: String) async throws {
        struct SetBody: Encodable {
            let newPassword: String
            enum CodingKeys: String, CodingKey {
                case newPassword = "new_password"
            }
        }
        struct SetResponse: Codable {
            let success: Bool
            let message: String?
        }

        guard let url = URL(string: "\(APIEndpoints.baseURL)\(APIEndpoints.Auth.setNewPassword)") else {
            throw AuthError.networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(recoveryAccessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(SetBody(newPassword: newPassword))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.networkError }

        if !(200...204).contains(http.statusCode) {
            // Surface the backend's error detail when present so the UI can
            // show "password too weak" etc instead of a generic message.
            let detail = (try? JSONDecoder().decode(SimpleErrorResponse.self, from: data))?.detail
            throw AuthError.serverError(http.statusCode, detail)
        }

        let decoded = try JSONDecoder().decode(SetResponse.self, from: data)
        if !decoded.success {
            throw AuthError.serverError(http.statusCode, decoded.message)
        }
    }

    // MARK: - User Onboarding

    func completeOnboarding() {
        isOnboarded = true
    }

    /// Resets onboarding status to false (for testing/debugging purposes)
    func resetOnboarding() {
        isOnboarded = false
    }

    // MARK: - AI Consent (Apple Guideline 5.1.1(i))

    /// True once the user has accepted AI processing of their voice and
    /// conversation data, AND the accepted policy version matches the
    /// current backend policy version. Read on app launch and before any
    /// agent conversation; if false, the consent screen must be presented
    /// before sending any data to OpenAI / Anthropic / ElevenLabs.
    var aiConsentGranted: Bool {
        guard let key = aiConsentKey("granted") else { return false }
        return userDefaults.bool(forKey: key)
    }

    /// Per-user key for the local AI-consent mirror. Scoping by user id
    /// stops a second user on a shared device (common for this audience
    /// with caregivers) from inheriting a prior user's cached consent
    /// and skipping the Apple 5.1.1(i) consent screen. Returns nil when
    /// no user is signed in, so reads safely default to "not consented".
    private func aiConsentKey(_ suffix: String) -> String? {
        guard let uid = currentUser?.id else { return nil }
        return "ai_consent.\(uid).\(suffix)"
    }

    /// Privacy-policy version string captured at the time the user
    /// accepted consent. When this falls behind the current /legal/privacy
    /// last_updated value AND the policy has materially changed, we
    /// re-prompt for consent.
    var aiConsentPolicyVersion: String? {
        guard let key = aiConsentKey("policy_version") else { return nil }
        return userDefaults.string(forKey: key)
    }

    /// Record (or withdraw) AI processing consent. Sends to backend so
    /// the decision survives reinstalls and is auditable, then mirrors
    /// the result locally for fast reads.
    func recordAIConsent(granted: Bool, policyVersion: String) async throws {
        struct Body: Encodable {
            let granted: Bool
            let policy_version: String
        }
        struct Response: Codable {
            let ai_consent_granted_at: String?
            let ai_consent_policy_version: String?
        }

        let body = try JSONEncoder().encode(Body(granted: granted, policy_version: policyVersion))
        let response: Response = try await NetworkService.shared.authenticatedRequest(
            endpoint: APIEndpoints.Preferences.aiConsent,
            method: .POST,
            body: body,
            responseType: Response.self
        )

        if let grantedKey = aiConsentKey("granted") {
            userDefaults.set(response.ai_consent_granted_at != nil, forKey: grantedKey)
        }
        if let versionKey = aiConsentKey("policy_version") {
            userDefaults.set(response.ai_consent_policy_version, forKey: versionKey)
        }
    }

    /// Hydrate consent state from the server. Call on app launch and
    /// after sign-in so `aiConsentGranted` reflects the source of truth.
    func refreshAIConsentFromServer() async {
        struct PrefsResponse: Codable {
            let ai_consent_granted_at: String?
            let ai_consent_policy_version: String?
        }
        do {
            let prefs: PrefsResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: APIEndpoints.Preferences.get,
                method: .GET,
                body: nil,
                responseType: PrefsResponse.self
            )
            if let grantedKey = aiConsentKey("granted") {
                userDefaults.set(prefs.ai_consent_granted_at != nil, forKey: grantedKey)
            }
            if let versionKey = aiConsentKey("policy_version") {
                userDefaults.set(prefs.ai_consent_policy_version, forKey: versionKey)
            }
        } catch {
            // Non-fatal — local cache stays as-is. Caller decides whether
            // to gate features on the cached value.
            Logger.warning("Failed to refresh AI consent from server: \(error)")
        }
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

        // Mark this device as one that's seen a signed-in user. Used to skip
        // the marketing carousel after sign-out — returning users go straight
        // to SignInView. Persists across sign-outs by design.
        userDefaults.set(true, forKey: "has_signed_in_before")

        Logger.info("UserManager.applySignInState: userId=\(user.id), isResolvingDestination=true")

        saveUserToStorage()

        // Hydrate AI-consent from the server (the source of truth) now that
        // currentUser is set, so a fresh sign-in never gates on a stale or
        // absent local mirror. Previously this call had no callers, so the
        // per-user consent state was never reconciled after sign-in.
        Task { await refreshAIConsentFromServer() }

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

        // Found a stored user — this device has seen sign-in before.
        // Backfills the flag for users upgrading past the change that introduced it.
        userDefaults.set(true, forKey: "has_signed_in_before")

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
