//
//  AuthServiceProtocol.swift
//  Halo-fi-IOS
//
//  Protocol for authentication service operations.
//

import Foundation

/// Protocol defining authentication service operations.
/// Enables dependency injection and mocking for tests.
protocol AuthServiceProtocol {
    /// Authenticates a user with phone number and password.
    /// - Parameters:
    ///   - phoneNumber: The user's phone number
    ///   - password: The user's password
    /// - Returns: LoginResponse containing tokens and user info
    func login(phoneNumber: String, password: String) async throws -> LoginResponse

    func socialLogin(provider: String, idToken: String, nonce: String?) async throws -> LoginResponse

    /// Registers a new user.
    /// - Parameters:
    ///   - firstName: User's first name
    ///   - lastName: User's last name
    ///   - email: User's email address
    ///   - phone: User's phone number
    ///   - password: User's password
    ///   - dateOfBirth: User's date of birth
    func register(
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        password: String,
        dateOfBirth: Date
    ) async throws

    /// Refreshes an expired access token.
    /// - Parameter refreshToken: The refresh token to use
    /// - Returns: RefreshTokenResponse with fresh tokens
    func refreshToken(refreshToken: String) async throws -> RefreshTokenResponse

    /// Fetches the authenticated user's profile.
    /// - Returns: UserProfileResponse with profile data
    func getUserProfile() async throws -> UserProfileResponse

    /// Updates the authenticated user's profile.
    /// - Parameter request: The profile update request
    /// - Returns: Updated UserProfileResponse
    func updateUserProfile(request: UpdateUserProfileRequest) async throws -> UserProfileResponse

    /// Logs out the current user.
    /// - Parameter accessToken: The current access token
    func logout(accessToken: String) async throws

    /// Deletes the user account and all associated data.
    /// - Parameter userId: The user's ID to delete
    /// - Note: This is a destructive operation. All data will be permanently deleted.
    func deleteAccount(userId: String) async throws
}

// MARK: - Mock Implementation for Testing

#if DEBUG
/// Mock authentication service for unit tests and previews.
actor MockAuthService: AuthServiceProtocol {
    var shouldSucceed = true
    var mockUser: UserProfileResponse?
    var mockLoginResponse: LoginResponse?

    func login(phoneNumber: String, password: String) async throws -> LoginResponse {
        guard shouldSucceed, let response = mockLoginResponse else {
            throw AuthError.invalidCredentials
        }
        return response
    }

    func socialLogin(provider: String, idToken: String, nonce: String?) async throws -> LoginResponse {
        guard shouldSucceed, let response = mockLoginResponse else {
            throw AuthError.invalidCredentials
        }
        return response
    }

    func register(
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        password: String,
        dateOfBirth: Date
    ) async throws {
        guard shouldSucceed else {
            throw AuthError.networkError
        }
    }

    func refreshToken(refreshToken: String) async throws -> RefreshTokenResponse {
        throw AuthError.notImplemented
    }

    func getUserProfile() async throws -> UserProfileResponse {
        guard shouldSucceed, let user = mockUser else {
            throw AuthError.notAuthenticated
        }
        return user
    }

    func updateUserProfile(request: UpdateUserProfileRequest) async throws -> UserProfileResponse {
        guard shouldSucceed, let user = mockUser else {
            throw AuthError.notAuthenticated
        }
        return user
    }

    func logout(accessToken: String) async throws {
        guard shouldSucceed else {
            throw AuthError.networkError
        }
    }

    func deleteAccount(userId: String) async throws {
        guard shouldSucceed else {
            throw AuthError.networkError
        }
    }
}
#endif
