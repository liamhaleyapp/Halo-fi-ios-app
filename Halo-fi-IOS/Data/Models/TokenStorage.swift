//
//  TokenStorage.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/13/25.
//
import Foundation

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
