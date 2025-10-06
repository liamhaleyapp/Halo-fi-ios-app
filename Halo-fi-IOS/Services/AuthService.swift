//
//  AuthService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Authentication Service
class AuthService {
    static let shared = AuthService()
    
    private let baseURL = "https://halofiapp-production.up.railway.app"
    private let session = URLSession.shared
    
    private init() {}
    
    // MARK: - Login
    func login(email: String, password: String) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/auth/login")!
        
        let loginRequest = LoginRequest(
            email: email,
            password: password
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(loginRequest)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        
        switch httpResponse.statusCode {
        case 200:
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            return authResponse
        case 422:
            let validationError = try JSONDecoder().decode(ValidationError.self, from: data)
            throw AuthError.validationError(validationError.detail)
        case 401:
            throw AuthError.invalidCredentials
        default:
            throw AuthError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Register
    func register(name: String, email: String, phone: String, password: String) async throws {
        let urlString = "\(baseURL)/users/signup"
        print("🔵 AuthService: Base URL: \(baseURL)")
        print("🔵 AuthService: Full URL string: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ AuthService: Invalid URL: \(urlString)")
            throw AuthError.networkError
        }
        
        print("🔵 AuthService: Starting signup request to: \(url)")
        
        let registerRequest = SignupRequest(
            name: name,
            email: email,
            phone: phone,
            password: password
        )
        
        // Log request data (without password for security)
        print("🔵 AuthService: Request data - name: \(name), email: \(email), phone: \(phone)")
        
        // Validate required fields
        if name.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty {
            print("❌ AuthService: Missing required fields")
            throw AuthError.validationError([])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let requestBody = try JSONEncoder().encode(registerRequest)
            request.httpBody = requestBody
            
            // Log the JSON string for debugging
            if let jsonString = String(data: requestBody, encoding: .utf8) {
                print("🔵 AuthService: Request JSON: \(jsonString)")
            }
            print("🔵 AuthService: Request body encoded successfully")
        } catch {
            print("❌ AuthService: Failed to encode request body: \(error)")
            throw AuthError.networkError
        }
        
        print("🔵 AuthService: Making network request...")
        let (data, response) = try await session.data(for: request)
        print("🔵 AuthService: Received response")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ AuthService: Invalid response type")
            throw AuthError.networkError
        }
        
        print("🔵 AuthService: Response status code: \(httpResponse.statusCode)")
        print("🔵 AuthService: Response headers: \(httpResponse.allHeaderFields)")
        
        // Log response body for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔵 AuthService: Response body: \(responseString)")
        } else {
            print("🔵 AuthService: Could not decode response body as string")
        }
        
        switch httpResponse.statusCode {
        case 201:
            print("✅ AuthService: Signup successful")
            return
        case 422:
            print("⚠️ AuthService: Validation error")
            let validationError = try JSONDecoder().decode(ValidationError.self, from: data)
            print("⚠️ AuthService: Validation details: \(validationError.detail)")
            throw AuthError.validationError(validationError.detail)
        case 409:
            print("⚠️ AuthService: Email already exists")
            throw AuthError.emailAlreadyExists
        case 500:
            print("❌ AuthService: Server error 500")
            print("❌ AuthService: Server response: \(String(data: data, encoding: .utf8) ?? "No response body")")
            print("❌ AuthService: This suggests a server-side issue. Possible causes:")
            print("❌ AuthService: - Database connection problem")
            print("❌ AuthService: - Validation logic error")
            print("❌ AuthService: - Missing server configuration")
            print("❌ AuthService: - Email format requirements")
            print("❌ AuthService: - Phone number format requirements")
            throw AuthError.serverError(httpResponse.statusCode)
        default:
            print("❌ AuthService: Unexpected status code: \(httpResponse.statusCode)")
            throw AuthError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Refresh Token
    // TODO: Implement when refresh endpoint is available in the API
    // Currently not available in the API documentation
    func refreshToken(refreshToken: String) async throws -> AuthResponse {
        throw AuthError.serverError(501) // Not implemented
    }
    
    // MARK: - Logout
    // TODO: Implement when logout endpoint is available in the API
    // Currently not available in the API documentation
    func logout(accessToken: String) async throws {
        // For now, just clear local tokens
        // Server-side logout not available yet
        throw AuthError.serverError(501) // Not implemented
    }
}

