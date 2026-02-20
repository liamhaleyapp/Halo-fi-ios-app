//
//  TokenStorage.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/13/25.
//
import Foundation
import Security

struct TokenStorage: TokenStorageProtocol {
  /// Environment-specific service name to isolate sandbox/production auth state
  private let service = AppEnvironment.isProdPlaid ? "com.halofi.ios.prod" : "com.halofi.ios.sandbox"
  private let accessTokenAccount = "accessToken"
  private let refreshTokenAccount = "refreshToken"
  private let tokenExpiryAccount = "tokenExpiry"
  
  // MARK: - Save Tokens
  
  func saveTokens(accessToken: String, refreshToken: String, expiresIn: Int) {
    let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
    
    // Save access token
    saveToKeychain(key: accessTokenAccount, value: accessToken)
    
    // Save refresh token
    saveToKeychain(key: refreshTokenAccount, value: refreshToken)
    
    // Save expiry date
    let expiryData = try? JSONEncoder().encode(expiryDate)
    saveToKeychain(key: tokenExpiryAccount, data: expiryData)
  }
  
  // Alternative method that uses the exact expiration timestamp from server
  func saveTokensWithExpiration(accessToken: String, refreshToken: String, expiresAt: Int) {
    let expiryDate = Date(timeIntervalSince1970: TimeInterval(expiresAt))
    
    // Save access token
    saveToKeychain(key: accessTokenAccount, value: accessToken)
    
    // Save refresh token
    saveToKeychain(key: refreshTokenAccount, value: refreshToken)
    
    // Save expiry date using exact server timestamp
    let expiryData = try? JSONEncoder().encode(expiryDate)
    saveToKeychain(key: tokenExpiryAccount, data: expiryData)
  }
  
  // MARK: - Retrieve Tokens
  
  func getAccessToken() -> String? {
    return getFromKeychain(key: accessTokenAccount)
  }
  
  func getRefreshToken() -> String? {
    return getFromKeychain(key: refreshTokenAccount)
  }
  
  func isTokenValid() -> Bool {
    guard let expiryData = getDataFromKeychain(key: tokenExpiryAccount),
          let expiryDate = try? JSONDecoder().decode(Date.self, from: expiryData) else {
      return false
    }
    return expiryDate > Date()
  }
  
  // MARK: - Clear Tokens
  
  func clearTokens() {
    deleteFromKeychain(key: accessTokenAccount)
    deleteFromKeychain(key: refreshTokenAccount)
    deleteFromKeychain(key: tokenExpiryAccount)
  }
  
  // MARK: - Keychain Helper Methods
  
  private func saveToKeychain(key: String, value: String) {
    guard let data = value.data(using: .utf8) else { return }
    saveToKeychain(key: key, data: data)
  }
  
  private func saveToKeychain(key: String, data: Data?) {
    guard let data = data else { return }
    
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    
    // Delete any existing item first
    SecItemDelete(query as CFDictionary)
    
    // Add the new item
    let status = SecItemAdd(query as CFDictionary, nil)
    if status != errSecSuccess {
      print("❌ Failed to save \(key) to keychain. Status: \(status)")
    }
  }
  
  private func getFromKeychain(key: String) -> String? {
    guard let data = getDataFromKeychain(key: key) else { return nil }
    return String(data: data, encoding: .utf8)
  }
  
  private func getDataFromKeychain(key: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    
    if status == errSecSuccess {
      return result as? Data
    } else if status == errSecItemNotFound {
      return nil
    } else {
      print("❌ Failed to retrieve \(key) from keychain. Status: \(status)")
      return nil
    }
  }
  
  private func deleteFromKeychain(key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      print("❌ Failed to delete \(key) from keychain. Status: \(status)")
    }
  }
}
