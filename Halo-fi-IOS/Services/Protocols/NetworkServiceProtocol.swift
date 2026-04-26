//
//  NetworkServiceProtocol.swift
//  Halo-fi-IOS
//
//  Protocol for network request operations.
//

import Foundation

/// Protocol defining network request operations.
/// Enables dependency injection and mocking for tests.
protocol NetworkServiceProtocol {
    /// Performs an authenticated HTTP request with the current access token.
    /// - Parameters:
    ///   - endpoint: The API endpoint path (e.g., "/api/v1/users/me")
    ///   - method: The HTTP method to use
    ///   - body: Optional request body as Data
    ///   - responseType: The expected response type
    /// - Returns: Decoded response of the specified type
    /// - Throws: AuthError for authentication or network failures
    func authenticatedRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod,
        body: Data?,
        responseType: T.Type
    ) async throws -> T

    /// Performs a public HTTP request without authentication.
    /// - Parameters:
    ///   - endpoint: The API endpoint path
    ///   - method: The HTTP method to use
    ///   - body: Optional request body as Data
    ///   - responseType: The expected response type
    /// - Returns: Decoded response of the specified type
    /// - Throws: AuthError for network failures
    func publicRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod,
        body: Data?,
        responseType: T.Type
    ) async throws -> T

    /// Performs an authenticated GET that returns raw bytes — for
    /// non-JSON downloads like CSV / PDF exports. The bytes are
    /// untouched; caller writes them to a file or processes in
    /// memory. Honors the same token-refresh path as the JSON
    /// authenticatedRequest.
    func authenticatedRawDataRequest(
        endpoint: String
    ) async throws -> Data
}

// MARK: - Default Parameter Extensions

extension NetworkServiceProtocol {
    func authenticatedRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        try await authenticatedRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            responseType: responseType
        )
    }

    func publicRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        try await publicRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            responseType: responseType
        )
    }
}

// MARK: - Mock Implementation for Testing

#if DEBUG
/// Mock network service for unit tests and previews.
final class MockNetworkService: NetworkServiceProtocol {
    var mockResponses: [String: Any] = [:]
    var mockError: Error?

    func setMockResponse<T: Codable>(_ response: T, for endpoint: String) {
        mockResponses[endpoint] = response
    }

    func setMockError(_ error: Error) {
        mockError = error
    }

    func authenticatedRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod,
        body: Data?,
        responseType: T.Type
    ) async throws -> T {
        if let error = mockError {
            throw error
        }
        guard let response = mockResponses[endpoint] as? T else {
            throw AuthError.networkError
        }
        return response
    }

    func publicRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod,
        body: Data?,
        responseType: T.Type
    ) async throws -> T {
        if let error = mockError {
            throw error
        }
        guard let response = mockResponses[endpoint] as? T else {
            throw AuthError.networkError
        }
        return response
    }

    func authenticatedRawDataRequest(endpoint: String) async throws -> Data {
        if let error = mockError {
            throw error
        }
        guard let response = mockResponses[endpoint] as? Data else {
            throw AuthError.networkError
        }
        return response
    }
}
#endif
