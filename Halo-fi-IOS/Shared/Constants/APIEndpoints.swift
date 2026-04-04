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

        /// POST - Social login (Apple, Google).
        static let socialLogin = "/auth/social-login"

        /// GET/PUT - Current user profile.
        static let me = "/auth/me"

        /// POST - Logout (if implemented).
        static let logout = "/auth/logout"

        /// POST - Request password reset email.
        static let resetPassword = "/auth/reset-password"
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

        /// GET - Fetch all linked items (connected institutions).
        static let multiItems = "/bank/multi-items"

        /// GET - Fetch all accounts summary.
        static let accounts = "/bank/accounts"

        /// GET - Fetch accounts for a specific item.
        /// Usage: `Bank.accountsForItem(itemId)`
        static func accountsForItem(_ itemId: String) -> String {
            "/bank/\(itemId)/account"
        }

        /// GET - Fetch transactions with optional filters (deprecated).
        static let transactions = "/bank/transactions"

        /// GET - Sync and get transactions for a specific item.
        /// Usage: `Bank.syncTransactions(itemId)` where itemId is the internal UUID (not plaid_item_id)
        static func syncTransactions(_ itemId: String) -> String {
            "/bank/sync/\(itemId)/transactions"
        }

        /// POST - Sync multiple items.
        static let multiItemsSync = "/bank/multi-items/sync"

        /// POST - Sync a specific item.
        /// Usage: `Bank.syncItem(itemId)` where itemId is the internal UUID (not plaid_item_id)
        static func syncItem(_ itemId: String) -> String {
            "/bank/sync/\(itemId)"
        }

        /// DELETE - Disconnect multiple bank items.
        /// Usage: `Bank.multiItemsDelete` with body containing item_ids array
        static let multiItemsDelete = "/bank/multi-items/delete"

        /// GET - Check bank service health.
        static let health = "/bank/health"

        /// POST - Register link session ID for webhook processing.
        /// Maps link_session_id to user in Redis for multi-item link webhooks.
        static let linkSessionRegister = "/bank/link-session/register"
    }

    // MARK: - Sandbox (Debug Only)

    enum Sandbox {
        /// POST - Create sandbox items directly (bypasses Plaid Link).
        /// Only available in sandbox environment.
        static let createMultiItems = "/bank/sandbox/create-multi-items"
    }

    // MARK: - Agent

    enum Agent {
        /// POST - Get ElevenLabs STT token for voice transcription.
        static let sttToken = "/agent/stt/token"
    }

    // MARK: - Preferences

    enum Preferences {
        static let get = "/users/preferences"
        static let update = "/users/preferences"
        static let voices = "/users/voices"
    }

    // MARK: - Legal
    enum Legal {
        static let terms = "/legal/terms"
        static let privacy = "/legal/privacy"
    }

    // MARK: - WebSocket

    enum WebSocket {
        /// Voice conversation WebSocket endpoint (deprecated - use ElevenLabs STT).
        static let voice = "/ws/voice"

        /// Full WebSocket URL for voice (deprecated).
        static var voiceURL: String {
            baseURL.replacingOccurrences(of: "https://", with: "wss://") + voice
        }

        /// Agent WebSocket endpoint.
        static let agent = "/agent/ws"

        /// Full WebSocket URL for agent.
        static var agentURL: String {
            baseURL.replacingOccurrences(of: "https://", with: "wss://") + agent
        }
    }
}
