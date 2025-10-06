//
//  AuthModels.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Request Models
struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct SignupRequest: Codable {
    let name: String
    let email: String
    let phone: String
    let password: String
}

struct RefreshTokenRequest: Codable {
    let refreshToken: String
}

// MARK: - Response Models
struct AuthResponse: Codable {
    let success: Bool
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let authUser: AuthUser
    
    enum CodingKeys: String, CodingKey {
        case success
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case authUser = "auth_user"
    }
}

struct AuthUser: Codable {
    let authUserId: String
    let email: String
    let emailConfirmed: Bool
    let phoneConfirmed: Bool
    let provider: String
    let isActive: Bool
    let createdAt: String
    let lastSignInAt: String
    let role: String
    
    enum CodingKeys: String, CodingKey {
        case authUserId = "auth_user_id"
        case email
        case emailConfirmed = "email_confirmed"
        case phoneConfirmed = "phone_confirmed"
        case provider
        case isActive = "is_active"
        case createdAt = "created_at"
        case lastSignInAt = "last_sign_in_at"
        case role
    }
}

// MARK: - Error Models
struct ValidationError: Codable {
    let detail: [ValidationErrorDetail]
}

struct ValidationErrorDetail: Codable {
    let loc: [String]
    let msg: String
    let type: String
}

// MARK: - Token Storage
struct TokenStorage {
    private let userDefaults = UserDefaults.standard
    private let accessTokenKey = "accessToken"
    private let refreshTokenKey = "refreshToken"
    private let tokenExpiryKey = "tokenExpiry"
    
    func saveTokens(accessToken: String, refreshToken: String, expiresIn: Int) {
        let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        
        userDefaults.set(accessToken, forKey: accessTokenKey)
        userDefaults.set(refreshToken, forKey: refreshTokenKey)
        userDefaults.set(expiryDate, forKey: tokenExpiryKey)
    }
    
    func getAccessToken() -> String? {
        return userDefaults.string(forKey: accessTokenKey)
    }
    
    func getRefreshToken() -> String? {
        return userDefaults.string(forKey: refreshTokenKey)
    }
    
    func isTokenValid() -> Bool {
        guard let expiryDate = userDefaults.object(forKey: tokenExpiryKey) as? Date else {
            return false
        }
        return expiryDate > Date()
    }
    
    func clearTokens() {
        userDefaults.removeObject(forKey: accessTokenKey)
        userDefaults.removeObject(forKey: refreshTokenKey)
        userDefaults.removeObject(forKey: tokenExpiryKey)
    }
}
