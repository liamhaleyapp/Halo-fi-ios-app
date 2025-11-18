//
//  NetworkService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Network Service
class NetworkService {
    static let shared = NetworkService()
    
    private let baseURL = "https://halofiapp-production.up.railway.app"
    private let session = URLSession.shared
    private let tokenStorage = TokenStorage()
    
    private init() {}
    
    // MARK: - Authenticated Requests
    
    func authenticatedRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        let request = try await createAuthenticatedRequest(
            endpoint: endpoint,
            method: method,
            body: body
        )
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        
        // Handle token expiration
        if httpResponse.statusCode == 401 {
            // TODO: Implement token refresh when endpoint is available
            // For now, just throw token expired error
            throw AuthError.tokenExpired
        }
        
        // Accept both 200 (OK) and 201 (Created) as success status codes
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            // Handle empty responses (e.g., 201 Created with no body)
            if data.isEmpty {
                // Try to decode from empty JSON object
                let emptyJSON = "{}".data(using: .utf8)!
                return try JSONDecoder().decode(T.self, from: emptyJSON)
            }
            return try JSONDecoder().decode(T.self, from: data)
        } else {
            // Log error without sensitive data (sanitized for security)
            // SECURITY: Don't log full response as it may contain sensitive tokens/data
            let sanitizedResponse = sanitizeErrorResponse(data)
            print("❌ Network Error [\(httpResponse.statusCode)]:")
            print("   Endpoint: \(endpoint)")
            if let sanitized = sanitizedResponse {
                print("   Response: \(sanitized)")
            }
            
            // Try to parse error responses (400 Bad Request or 422 Unprocessable Entity)
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 422 {
                // First, try to parse as ValidationError (array format)
                if let validationError = try? JSONDecoder().decode(ValidationError.self, from: data) {
                    throw AuthError.validationError(validationError.detail)
                }
                
                // If that fails, try to parse as SimpleErrorResponse (string detail format)
                if let simpleError = try? JSONDecoder().decode(SimpleErrorResponse.self, from: data) {
                    throw AuthError.serverError(httpResponse.statusCode, simpleError.detail)
                }
                
                // If both fail, try to extract detail from raw JSON
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = json["detail"] as? String {
                    throw AuthError.serverError(httpResponse.statusCode, detail)
                }
                
                // Fallback for 422 - validation error with empty details
                if httpResponse.statusCode == 422 {
                    throw AuthError.validationError([])
                }
            }
            
            // For other error codes, try to extract detail message if available
            var errorDetail: String? = nil
            if let simpleError = try? JSONDecoder().decode(SimpleErrorResponse.self, from: data) {
                errorDetail = simpleError.detail
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let detail = json["detail"] as? String {
                errorDetail = detail
            }
            
            throw AuthError.serverError(httpResponse.statusCode, errorDetail)
        }
    }
    
    // MARK: - Public Requests (No Authentication)
    
    func publicRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        let url = URL(string: "\(baseURL)\(endpoint)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.networkError
        }
        
        // Accept both 200 (OK) and 201 (Created) as success status codes
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            // Handle empty responses (e.g., 201 Created with no body)
            if data.isEmpty {
                // Try to decode from empty JSON object
                let emptyJSON = "{}".data(using: .utf8)!
                return try JSONDecoder().decode(T.self, from: emptyJSON)
            }
            return try JSONDecoder().decode(T.self, from: data)
        } else {
            // Log error without sensitive data (sanitized for security)
            // SECURITY: Don't log full response as it may contain sensitive tokens/data
            let sanitizedResponse = sanitizeErrorResponse(data)
            print("❌ Network Error [\(httpResponse.statusCode)]:")
            print("   Endpoint: \(endpoint)")
            if let sanitized = sanitizedResponse {
                print("   Response: \(sanitized)")
            }
            
            // Try to parse error responses (400 Bad Request or 422 Unprocessable Entity)
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 422 {
                // First, try to parse as ValidationError (array format)
                if let validationError = try? JSONDecoder().decode(ValidationError.self, from: data) {
                    throw AuthError.validationError(validationError.detail)
                }
                
                // If that fails, try to parse as SimpleErrorResponse (string detail format)
                if let simpleError = try? JSONDecoder().decode(SimpleErrorResponse.self, from: data) {
                    throw AuthError.serverError(httpResponse.statusCode, simpleError.detail)
                }
                
                // If both fail, try to extract detail from raw JSON
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = json["detail"] as? String {
                    throw AuthError.serverError(httpResponse.statusCode, detail)
                }
                
                // Fallback for 422 - validation error with empty details
                if httpResponse.statusCode == 422 {
                    throw AuthError.validationError([])
                }
            }
            
            // For other error codes, try to extract detail message if available
            var errorDetail: String? = nil
            if let simpleError = try? JSONDecoder().decode(SimpleErrorResponse.self, from: data) {
                errorDetail = simpleError.detail
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let detail = json["detail"] as? String {
                errorDetail = detail
            }
            
            throw AuthError.serverError(httpResponse.statusCode, errorDetail)
        }
    }
    
    // MARK: - Private Methods
    
    private func createAuthenticatedRequest(
        endpoint: String,
        method: HTTPMethod,
        body: Data?
    ) async throws -> URLRequest {
        guard let accessToken = tokenStorage.getAccessToken() else {
            throw AuthError.tokenExpired
        }
        
        let url = URL(string: "\(baseURL)\(endpoint)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.httpBody = body
        }
        
        return request
    }
    
    // TODO: Implement when refresh token endpoint is available
    private func refreshTokenAndRetry(refreshToken: String) async throws {
        throw AuthError.serverError(501, "Token refresh not implemented") // Not implemented
    }
    
    // MARK: - Security Helpers
    
    /// Sanitizes error response data to remove sensitive information before logging
    /// SECURITY: Removes tokens, passwords, and other sensitive fields from error logs
    private func sanitizeErrorResponse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // If not JSON, return truncated string (max 200 chars)
            if let string = String(data: data, encoding: .utf8) {
                return String(string.prefix(200))
            }
            return nil
        }
        
        var sanitized = json
        
        // Remove sensitive fields
        let sensitiveKeys = [
            "access_token", "refresh_token", "token", "public_token", "link_token",
            "password", "password_hash", "api_key", "secret", "authorization",
            "account_number", "routing_number", "ssn", "social_security"
        ]
        
        for key in sensitiveKeys {
            sanitized.removeValue(forKey: key)
            sanitized.removeValue(forKey: key.capitalized)
            sanitized.removeValue(forKey: key.uppercased())
        }
        
        // Convert back to JSON string
        if let sanitizedData = try? JSONSerialization.data(withJSONObject: sanitized, options: .prettyPrinted),
           let sanitizedString = String(data: sanitizedData, encoding: .utf8) {
            return sanitizedString
        }
        
        return nil
    }
}

// MARK: - HTTP Method Enum
enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
}
