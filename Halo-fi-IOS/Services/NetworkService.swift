//
//  NetworkService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Network Service

final class NetworkService {
    static let shared = NetworkService()

    private let baseURL: String
    private let session: URLSession
    private let tokenStorage: TokenStorage

    init(
        baseURL: String = "https://halofiapp-production.up.railway.app",
        session: URLSession = .shared,
        tokenStorage: TokenStorage = TokenStorage()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStorage = tokenStorage
    }

    // MARK: - Authenticated Requests

    func authenticatedRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        let request = try createAuthenticatedRequest(
            endpoint: endpoint,
            method: method,
            body: body
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.error("Invalid HTTP response")
            throw AuthError.networkError
        }

        Logger.networkResponse(statusCode: httpResponse.statusCode, dataSize: data.count)

        if httpResponse.statusCode == 401 {
            Logger.error("401 Unauthorized - Token expired or invalid")
            throw AuthError.tokenExpired
        }

        return try handleResponse(data: data, httpResponse: httpResponse, responseType: T.self)
    }

    // MARK: - Public Requests (No Authentication)

    func publicRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw AuthError.networkError
        }

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

        return try handleResponse(data: data, httpResponse: httpResponse, responseType: T.self)
    }

    // MARK: - Response Handling

    private func handleResponse<T: Codable>(
        data: Data,
        httpResponse: HTTPURLResponse,
        responseType: T.Type
    ) throws -> T {
        let statusCode = httpResponse.statusCode

        // Success: 200 OK, 201 Created, 204 No Content
        if (200...204).contains(statusCode) {
            return try decodeSuccessResponse(data: data, responseType: T.self)
        }

        // Error response
        throw parseErrorResponse(data: data, statusCode: statusCode)
    }

    private func decodeSuccessResponse<T: Codable>(data: Data, responseType: T.Type) throws -> T {
        if data.isEmpty {
            let emptyJSON = Data("{}".utf8)
            return try JSONDecoder().decode(T.self, from: emptyJSON)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func parseErrorResponse(data: Data, statusCode: Int) -> AuthError {
        // Handle validation errors (400, 422)
        if statusCode == 400 || statusCode == 422 {
            if let validationError = try? JSONDecoder().decode(ValidationError.self, from: data) {
                Logger.debug("Validation error: \(validationError.detail.map { $0.msg }.joined(separator: ", "))")
                return .validationError(validationError.detail)
            }

            if let simpleError = try? JSONDecoder().decode(SimpleErrorResponse.self, from: data) {
                Logger.debug("Simple error: \(simpleError.detail)")
                return .serverError(statusCode, simpleError.detail)
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                Logger.debug("JSON error detail: \(detail)")
                return .serverError(statusCode, detail)
            }

            if statusCode == 422 {
                return .validationError([])
            }
        }

        // Extract detail from other error responses
        let errorDetail = extractErrorDetail(from: data)
        Logger.error("Request failed: status=\(statusCode), detail=\(errorDetail ?? "none")")
        return .serverError(statusCode, errorDetail)
    }

    private func extractErrorDetail(from data: Data) -> String? {
        if let simpleError = try? JSONDecoder().decode(SimpleErrorResponse.self, from: data) {
            return simpleError.detail
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String {
            return detail
        }

        return nil
    }

    // MARK: - Request Creation

    private func createAuthenticatedRequest(
        endpoint: String,
        method: HTTPMethod,
        body: Data?
    ) throws -> URLRequest {
        guard let accessToken = tokenStorage.getAccessToken() else {
            Logger.error("No access token found")
            throw AuthError.tokenExpired
        }

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw AuthError.networkError
        }

        Logger.networkRequest(endpoint: endpoint, method: method.rawValue, hasToken: true)

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.httpBody = body
        }

        return request
    }

    // MARK: - Token Refresh (Not Implemented)

    private func refreshTokenAndRetry(refreshToken: String) async throws {
        // TODO: Implement when refresh token endpoint is available
        throw AuthError.notImplemented
    }
}

// MARK: - HTTP Method Enum

enum HTTPMethod: String {
    case GET
    case POST
    case PUT
    case DELETE
    case PATCH
}
