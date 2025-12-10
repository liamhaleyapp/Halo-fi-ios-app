//
//  TokenStorageProtocol.swift
//  Halo-fi-IOS
//
//  Protocol for secure token storage operations.
//

import Foundation

/// Protocol defining token storage operations for authentication.
/// Enables dependency injection and mocking for tests.
protocol TokenStorageProtocol {
    /// Retrieves the current access token, if available.
    func getAccessToken() -> String?

    /// Retrieves the current refresh token, if available.
    func getRefreshToken() -> String?

    /// Checks if the current access token is still valid (not expired).
    func isTokenValid() -> Bool

    /// Saves authentication tokens with a relative expiration time.
    /// - Parameters:
    ///   - accessToken: The access token to store
    ///   - refreshToken: The refresh token to store
    ///   - expiresIn: Seconds until the access token expires
    func saveTokens(accessToken: String, refreshToken: String, expiresIn: Int)

    /// Saves authentication tokens with an absolute expiration timestamp.
    /// - Parameters:
    ///   - accessToken: The access token to store
    ///   - refreshToken: The refresh token to store
    ///   - expiresAt: Unix timestamp when the access token expires
    func saveTokensWithExpiration(accessToken: String, refreshToken: String, expiresAt: Int)

    /// Removes all stored tokens from secure storage.
    func clearTokens()
}

// MARK: - Mock Implementation for Testing

#if DEBUG
/// Mock token storage for unit tests and previews.
final class MockTokenStorage: TokenStorageProtocol {
    var accessToken: String?
    var refreshToken: String?
    var tokenExpiry: Date?

    func getAccessToken() -> String? { accessToken }
    func getRefreshToken() -> String? { refreshToken }

    func isTokenValid() -> Bool {
        guard let expiry = tokenExpiry else { return false }
        return expiry > Date()
    }

    func saveTokens(accessToken: String, refreshToken: String, expiresIn: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
    }

    func saveTokensWithExpiration(accessToken: String, refreshToken: String, expiresAt: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiry = Date(timeIntervalSince1970: TimeInterval(expiresAt))
    }

    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
    }
}
#endif
