//
//  RefreshTokenRequest.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/13/25.
//
import Foundation

struct RefreshTokenRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}
