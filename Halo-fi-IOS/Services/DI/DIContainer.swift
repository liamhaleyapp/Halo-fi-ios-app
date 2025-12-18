//
//  DIContainer.swift
//  Halo-fi-IOS
//
//  Dependency injection container that owns all service instances.
//  Provides explicit dependency graph and enables testing with mocks.
//

import SwiftUI

/// Central dependency injection container for the app.
/// Owns all service instances and manages their lifecycle.
@Observable
@MainActor
final class DIContainer {
    // MARK: - Core Services (Layer 1-2)

    /// Secure token storage for authentication
    let tokenStorage: TokenStorageProtocol

    /// HTTP networking layer
    let networkService: NetworkServiceProtocol

    // MARK: - Business Services (Layer 3)

    /// Authentication operations (login, register, profile)
    let authService: AuthServiceProtocol

    /// Banking operations (accounts, transactions, sync)
    let bankService: BankServiceProtocol

    // MARK: - State Managers (Layer 4)

    /// User authentication state and profile
    let userManager: UserManager

    /// Bank data state and caching
    let bankDataManager: BankDataManager

    /// Permission state management
    let permissionManager: PermissionManager

    // MARK: - Initialization

    /// Creates the production dependency container with real implementations.
    init() {
        // Layer 1: Foundation
        let tokenStorage = TokenStorage()
        self.tokenStorage = tokenStorage

        // Layer 2: Networking
        let networkService = NetworkService(tokenStorage: tokenStorage)
        self.networkService = networkService

        // Layer 3: Business Services
        let authService = AuthService(networkService: networkService)
        self.authService = authService

        let bankService = BankService(networkService: networkService)
        self.bankService = bankService

        // Layer 4: State Managers
        let userManager = UserManager(tokenStorage: tokenStorage, authService: authService)
        let bankDataManager = BankDataManager(bankService: bankService)
        self.userManager = userManager
        self.bankDataManager = bankDataManager
        self.permissionManager = PermissionManager.shared

        // Wire up cross-manager dependencies
        userManager.setBankDataManager(bankDataManager)
    }

    /// Creates a dependency container with custom implementations (for testing).
    /// - Parameters:
    ///   - tokenStorage: Custom token storage implementation
    ///   - networkService: Custom network service implementation
    ///   - authService: Custom auth service implementation
    ///   - bankService: Custom bank service implementation
    init(
        tokenStorage: TokenStorageProtocol,
        networkService: NetworkServiceProtocol,
        authService: AuthServiceProtocol,
        bankService: BankServiceProtocol
    ) {
        self.tokenStorage = tokenStorage
        self.networkService = networkService
        self.authService = authService
        self.bankService = bankService

        let userManager = UserManager(tokenStorage: tokenStorage, authService: authService)
        let bankDataManager = BankDataManager(bankService: bankService)
        self.userManager = userManager
        self.bankDataManager = bankDataManager
        self.permissionManager = PermissionManager.shared

        // Wire up cross-manager dependencies
        userManager.setBankDataManager(bankDataManager)
    }
}

// MARK: - Preview Support

#if DEBUG
extension DIContainer {
    /// Creates a mock container for SwiftUI previews.
    static var preview: DIContainer {
        DIContainer()
    }
}
#endif
