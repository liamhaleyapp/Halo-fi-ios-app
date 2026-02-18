//
//  RefreshTokenTests.swift.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 2/18/26.
//

import Foundation
import Testing
@testable import Halo_fi_IOS

struct RefreshTokenTests {
  
  @Test func requestEncodesToSnakeCase() throws {
    let request = RefreshTokenRequest(refreshToken: "test_token")
    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    
    #expect(json?["refresh_token"] as? String == "test_token")
  }
  
  @Test func responseDecodesFromSnakeCase() throws {
    let json = """
        {
            "success": true,
            "access_token": "new_access",
            "refresh_token": "new_refresh",
            "token_type": "bearer",
            "expires_in": 3600
        }
        """.data(using: .utf8)!
    
    let response = try JSONDecoder().decode(RefreshTokenResponse.self, from: json)
    
    #expect(response.success == true)
    #expect(response.accessToken == "new_access")
    #expect(response.refreshToken == "new_refresh")
    #expect(response.expiresIn == 3600)
  }
  
  @Test func responseComputesExpiresAt() throws {
    let json = """
        {"success": true, "access_token": "a", "refresh_token": "r", "token_type": "bearer", "expires_in": 3600}
        """.data(using: .utf8)!
    
    let before = Int(Date().timeIntervalSince1970)
    let response = try JSONDecoder().decode(RefreshTokenResponse.self, from: json)
    
    #expect(response.expiresAt >= before + 3600)
  }
}
