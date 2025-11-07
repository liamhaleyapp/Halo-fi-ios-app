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
            // Debug: Print raw response for /auth/me endpoint
            if endpoint.contains("/auth/me") {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("📥 Raw /auth/me Response (Status \(httpResponse.statusCode)):")
                    print(responseString)
                }
            }
            
            // Handle empty responses (e.g., 201 Created with no body)
            if data.isEmpty {
                // Try to decode from empty JSON object
                let emptyJSON = "{}".data(using: .utf8)!
                return try JSONDecoder().decode(T.self, from: emptyJSON)
            }
            return try JSONDecoder().decode(T.self, from: data)
        } else {
            throw AuthError.serverError(httpResponse.statusCode)
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
            throw AuthError.serverError(httpResponse.statusCode)
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
        throw AuthError.serverError(501) // Not implemented
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
