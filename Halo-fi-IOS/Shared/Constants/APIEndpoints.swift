//
//  APIEndpoints.swift
//  Halo-fi-IOS
//
//  Centralized API endpoint constants.
//  All API paths should be defined here to ensure consistency
//  and make endpoint changes easier to manage.
//

import Foundation

enum APIEndpoints {

    // MARK: - Base URL

    /// Production API base URL.
    static let baseURL = "https://halofiapp-production.up.railway.app"

    // MARK: - Authentication

    enum Auth {
        /// POST - Login with phone and password.
        static let login = "/auth/login"

        /// GET/PUT - Current user profile.
        static let me = "/auth/me"

        /// POST - Logout (if implemented).
        static let logout = "/auth/logout"
    }

    // MARK: - User

    enum User {
        /// POST - Register new user.
        static let signup = "/users/signup"
    }

    // MARK: - Banking

    enum Bank {
        /// POST - Connect multiple bank accounts via Plaid.
        static let multiConnect = "/bank/multi-connect"

        /// POST - Create Plaid Link token for multi-item flow.
        static let multiLinkCreate = "/bank/multi-link/create"

        /// GET - Fetch all accounts summary.
        static let accounts = "/bank/accounts"

        /// GET - Fetch accounts for a specific item.
        /// Usage: `Bank.accountsForItem(itemId)`
        static func accountsForItem(_ itemId: String) -> String {
            "/bank/\(itemId)/account"
        }

        /// GET - Fetch transactions with optional filters (deprecated).
        static let transactions = "/bank/transactions"

        /// GET - Sync transactions for a specific item.
        /// Usage: `Bank.syncTransactions(plaidItemId)`
        static func syncTransactions(_ plaidItemId: String) -> String {
            "/bank/sync/transactions?plaid_item_id=\(plaidItemId)"
        }

        /// POST - Sync multiple items.
        static let multiItemsSync = "/bank/multi-items/sync"

        /// POST - Sync a specific item.
        /// Usage: `Bank.syncItem(plaidItemId)`
        static func syncItem(_ plaidItemId: String) -> String {
            "/bank/sync/\(plaidItemId)"
        }

        /// DELETE - Disconnect a bank account.
        /// Usage: `Bank.disconnect(plaidItemId)`
        static func disconnect(_ plaidItemId: String) -> String {
            "/bank/disconnect/\(plaidItemId)"
        }

        /// GET - Check bank service health.
        static let health = "/bank/health"
    }

    // MARK: - Sandbox (Debug Only)

    enum Sandbox {
        /// POST - Create sandbox items directly (bypasses Plaid Link).
        /// Only available in sandbox environment.
        static let createMultiItems = "/bank/sandbox/create-multi-items"
    }

    // MARK: - WebSocket

    enum WebSocket {
        /// Voice conversation WebSocket endpoint.
        static let voice = "/ws/voice"

        /// Full WebSocket URL for voice.
        static var voiceURL: String {
            baseURL.replacingOccurrences(of: "https://", with: "wss://") + voice
        }
    }
}
