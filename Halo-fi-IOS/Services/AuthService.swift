//
//  AuthService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Authentication Service

final class AuthService: AuthServiceProtocol {
    static let shared = AuthService()

    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol = NetworkService.shared) {
        self.networkService = networkService
    }

    // MARK: - Login

    func login(phoneNumber: String, password: String) async throws -> LoginResponse {
        let loginRequest = LoginRequest(
            phone: phoneNumber,
            password: password
        )

        let requestBody = try JSONEncoder().encode(loginRequest)

        return try await networkService.publicRequest(
            endpoint: "/auth/login",
            method: .POST,
            body: requestBody,
            responseType: LoginResponse.self
        )
    }

    // MARK: - Register

    func register(
        firstName: String,
        lastName: String,
        email: String,
        phone: String,
        password: String,
        dateOfBirth: Date
    ) async throws {
        if firstName.isEmpty || lastName.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty {
            throw AuthError.validationError([])
        }

        let registerRequest = SignupRequest(
            firstName: firstName,
            lastName: lastName,
            email: email,
            phone: phone,
            password: password,
            dateOfBirth: DateFormatting.formatForAPI(dateOfBirth)
        )

        let requestBody = try JSONEncoder().encode(registerRequest)

        _ = try await networkService.publicRequest(
            endpoint: "/users/signup",
            method: .POST,
            body: requestBody,
            responseType: SignupResponse.self
        )
    }

    // MARK: - Refresh Token

    // TODO: Implement when refresh endpoint is available in the API
    func refreshToken(refreshToken: String) async throws -> LoginResponse {
        throw AuthError.notImplemented
    }

    // MARK: - Get User Profile

    func getUserProfile() async throws -> UserProfileResponse {
        try await networkService.authenticatedRequest(
            endpoint: "/auth/me",
            method: .GET,
            responseType: UserProfileResponse.self
        )
    }

    // MARK: - Update User Profile

    func updateUserProfile(request: UpdateUserProfileRequest) async throws -> UserProfileResponse {
        let requestBody = try JSONEncoder().encode(request)

        return try await networkService.authenticatedRequest(
            endpoint: "/auth/me",
            method: .PUT,
            body: requestBody,
            responseType: UserProfileResponse.self
        )
    }

    // MARK: - Logout

    // TODO: Implement when logout endpoint is available in the API
    func logout(accessToken: String) async throws {
        throw AuthError.notImplemented
    }
}
