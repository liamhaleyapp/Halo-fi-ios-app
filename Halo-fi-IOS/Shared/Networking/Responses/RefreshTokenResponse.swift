//
//  RefreshTokenResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 2/18/26.
//

import Foundation

struct RefreshTokenResponse: Codable {
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

    /// Converts relative expiresIn (seconds) to absolute Unix timestamp
    var expiresAt: Int {
        Int(Date().timeIntervalSince1970) + expiresIn
    }
}
