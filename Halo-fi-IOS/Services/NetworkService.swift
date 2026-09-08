//
//  NetworkService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Token Refresh Coordinator

/// Coordinates token refresh to prevent multiple simultaneous refresh calls.
/// Uses Swift actor for thread-safe coordination since NetworkService is not @MainActor.
private actor TokenRefreshCoordinator {
    private struct Key: Hashable { let generation: UUID; let token: String }
    private var tasks: [Key: Task<Void, Error>] = [:]

    func refresh(using token: String, generation: UUID,
                 operation: @escaping () async throws -> Void) async throws {
        let key = Key(generation: generation, token: token)
        if let task = tasks[key] { return try await task.value }
        let task = Task { try await operation() }
        tasks[key] = task
        defer { tasks[key] = nil }
        try await task.value
    }
}

// MARK: - Session Expiry Notification

extension Notification.Name {
    /// Posted when the session is no longer valid and the user should be signed out.
    static let sessionExpired = Notification.Name("sessionExpired")
}

// MARK: - Network Service

final class NetworkService: NetworkServiceProtocol {
    static let shared = NetworkService()

    private let baseURL: String
    private let session: URLSession
    private let tokenStorage: TokenStorageProtocol
    private let refreshCoordinator = TokenRefreshCoordinator()
    private let lifetime: SessionLifetime

    init(
        baseURL: String = "https://halofiapp-production.up.railway.app",
        session: URLSession = .shared,
        tokenStorage: TokenStorageProtocol = TokenStorage(),
        lifetime: SessionLifetime = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStorage = tokenStorage
        self.lifetime = lifetime
    }

    // MARK: - Authenticated Requests

    func authenticatedRequest<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Data? = nil,
        responseType: T.Type
    ) async throws -> T {
        let generation = lifetime.current
        let data = try await authenticatedData(endpoint: endpoint, method: method, body: body, generation: generation)
        return try lifetime.withCurrent(generation) {
            try decodeSuccessResponse(data: data, responseType: responseType)
        }
    }

    func authenticatedRawDataRequest(endpoint: String) async throws -> Data {
        let generation = lifetime.current
        return try await authenticatedData(endpoint: endpoint, method: .GET, body: nil, generation: generation)
    }

    private func authenticatedData(endpoint: String, method: HTTPMethod, body: Data?, generation: UUID) async throws -> Data {
        for attempt in 0...1 {
            try Task.checkCancellation()
            let request = try lifetime.withCurrent(generation) {
                try createAuthenticatedRequest(endpoint: endpoint, method: method, body: body)
            }
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                try lifetime.check(generation)
                throw error
            }
            try lifetime.check(generation)
            guard let http = response as? HTTPURLResponse else { throw AuthError.networkError }
            if http.statusCode == 401 {
                if attempt == 0 {
                    try await refreshAfterUnauthorized(request: request, generation: generation)
                    continue
                }
                await notifySessionExpired(generation: generation)
                throw AuthError.tokenExpired
            }
            guard (200...299).contains(http.statusCode) else {
                throw parseErrorResponse(data: data, statusCode: http.statusCode)
            }
            return data
        }
        throw AuthError.tokenExpired
    }

    private func refreshAfterUnauthorized(request: URLRequest, generation: UUID) async throws {
        let refreshToken: String? = try lifetime.withCurrent(generation) {
            // Another request in this same session may already have refreshed.
            if let access = tokenStorage.getAccessToken(),
               request.value(forHTTPHeaderField: "Authorization") != "Bearer \(access)" { return nil }
            guard let token = tokenStorage.getRefreshToken() else { throw AuthError.tokenExpired }
            return token
        }
        guard let refreshToken else { return }
        do {
            try await refreshCoordinator.refresh(using: refreshToken, generation: generation) { [self] in
                try lifetime.check(generation)
                let response = try await performTokenRefresh(refreshToken)
                try lifetime.withCurrent(generation) {
                    tokenStorage.saveTokensWithExpiration(accessToken: response.accessToken,
                        refreshToken: response.refreshToken, expiresAt: response.expiresAt)
                }
            }
        } catch {
            try lifetime.check(generation)
            // Connectivity, server and decoding failures do not invalidate credentials.
            if Self.isRejectedRefresh(error) {
                await notifySessionExpired(generation: generation)
                throw AuthError.tokenExpired
            }
            throw error
        }
        try lifetime.check(generation)
    }

    static func isRejectedRefresh(_ error: Error) -> Bool {
        guard let auth = error as? AuthError else { return false }
        switch auth {
        case .invalidCredentials, .tokenExpired: return true
        case .serverError(let status, _): return status == 400 || status == 401 || status == 403
        default: return false
        }
    }

    /// Performs token refresh via the refresh endpoint.
    private func performTokenRefresh(_ refreshToken: String) async throws -> RefreshTokenResponse {
        let request = RefreshTokenRequest(refreshToken: refreshToken)
        let requestBody = try JSONEncoder().encode(request)

        return try await publicRequest(
            endpoint: "/auth/refresh-token",
            method: .POST,
            body: requestBody,
            responseType: RefreshTokenResponse.self
        )
    }

    /// Notifies the app that the session has expired and user should be signed out.
    @MainActor
    private func notifySessionExpired(generation: UUID) {
        guard lifetime.isCurrent(generation) else { return }
        NotificationCenter.default.post(name: .sessionExpired, object: nil)
    }

    /// Prepare sign-out cleanup while the departing account's token still
    /// exists. Sending this request never reads or refreshes a later session.
    func prepareDeviceRevocation(deviceToken: String) throws -> URLRequest {
        var request = try createAuthenticatedRequest(endpoint: "/me/devices/\(deviceToken)", method: .DELETE, body: nil)
        request.timeoutInterval = 15
        return request
    }

    func sendDeviceRevocation(_ request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthError.networkError
        }
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

        // Raw response body can contain balances/PII — DEBUG-only (F048).
        if let jsonString = String(data: data, encoding: .utf8) {
            Logger.sensitive("📦 Raw Response JSON:\n\(jsonString)")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func parseErrorResponse(data: Data, statusCode: Int) -> AuthError {
        // Log raw response for debugging
        if let rawString = String(data: data, encoding: .utf8) {
            Logger.debug("Error response (status \(statusCode)): \(rawString)")
        }

        // 1. Try APIErrorResponse: {"success": false, "error": "..."} or {"error": "..."}
        if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
           let errorMessage = apiError.errorMessage, !errorMessage.isEmpty {
            Logger.debug("API error: \(errorMessage)")
            return .serverError(statusCode, errorMessage)
        }

        // 2. Handle validation errors (400, 422)
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

        // 3. Extract detail from other error responses using fallback chain
        let errorDetail = extractErrorDetail(from: data)
        Logger.error("Request failed: status=\(statusCode), detail=\(errorDetail ?? "none")")
        return .serverError(statusCode, errorDetail)
    }

    private func extractErrorDetail(from data: Data) -> String? {
        // 1. Try APIErrorResponse format
        if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
           let errorMessage = apiError.errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }

        // 2. Try SimpleErrorResponse format ({"detail": "..."})
        if let simpleError = try? JSONDecoder().decode(SimpleErrorResponse.self, from: data) {
            return simpleError.detail
        }

        // 3. Try raw JSON with error, message, or detail keys
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? String, !error.isEmpty {
                return error
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
            if let detail = json["detail"] as? String, !detail.isEmpty {
                return detail
            }
        }

        // 4. Try plain text response
        if let plainText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plainText.isEmpty,
           !plainText.hasPrefix("{"),  // Not JSON
           !plainText.hasPrefix("<") {  // Not HTML
            return plainText
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

}

// MARK: - HTTP Method Enum

enum HTTPMethod: String {
    case GET
    case POST
    case PUT
    case DELETE
    case PATCH
}
