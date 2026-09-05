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

        /// POST - Request password reset via SMS to a phone number.
        /// Body: { phone }. Always returns 200 (anti-enumeration).
        static let resetPasswordSMS = "/auth/reset-password-sms"

        /// POST - Verify the 6-digit OTP from the password reset email.
        /// Returns a short-lived recovery access_token used by setNewPassword.
        static let verifyResetOTP = "/auth/verify-reset-otp"

        /// POST - Verify the 6-digit OTP from the password reset SMS.
        /// Body: { phone, token }. Returns same shape as verifyResetOTP.
        static let verifyResetSMSOTP = "/auth/verify-reset-sms-otp"

        /// POST - Set a new password. Requires the recovery access_token
        /// from verifyResetOTP as the Bearer auth header.
        static let setNewPassword = "/auth/set-new-password"

        /// POST - Verify the 6-digit phone OTP sent during signup.
        /// Body: { id_user, verification_token }.
        static let verifyPhoneCode = "/auth/verification_code"

        /// POST - Resend the phone OTP for a user that hasn't verified yet.
        /// Body: { user_auth_id }.
        static let resendPhoneCode = "/auth/resend_code"
    }

    // MARK: - User

    enum User {
        /// POST - Register new user.
        static let signup = "/users/signup"

        /// PATCH - Update the authenticated user's profile (including income fields).
        static let me = "/users/me"

        /// GET - Server-computed feature gating from the benefits profile.
        static let capabilities = "/users/me/capabilities"

        /// GET / PUT - Work-context profile (drives BWE/IRWE classifier).
        /// Phase 3a — captures intent that Plaid descriptions don't carry.
        static let workProfile = "/users/work-profile"
    }

    // MARK: - Attention + Income (2026-09-05)

    enum Attention {
        /// GET — what needs the user, most urgent first. POST `/{id}/dismiss` = Not now.
        static let me = "/me/attention"
        static func dismiss(_ cardId: String) -> String { "/me/attention/\(cardId)/dismiss" }
    }

    enum Income {
        /// GET — recent money-in with labels.
        static let deposits = "/income/deposits"
        /// POST — say what a deposit was. PATCH/DELETE `/{id}`.
        static let labels = "/income/labels"
        static func label(_ id: String) -> String { "/income/labels/\(id)" }
        /// GET — learned sources + this month's work income.
        static let summary = "/income/summary"
    }

    // MARK: - Budget

    enum Budget {
        /// GET - Aggregated budget view (spending, income, SSI, alerts).
        static let overview = "/budget/overview"

        /// PATCH / DELETE - a single category (monthly limit / remove).
        static func category(_ categoryId: String) -> String {
            "/budget/categories/\(categoryId)"
        }

        /// POST - Add a category to the active budget.
        static let categories = "/budget/categories"

        /// GET - Smart suggestion (90-day medians). POST …/apply creates the budget.
        static let suggestions = "/budget/suggestions"
        static let applySuggestions = "/budget/suggestions/apply"
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
        static func accountNickname(_ accountId: String) -> String {
            "/bank/accounts/\(accountId)/nickname"
        }

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

        // MARK: Manual accounts (non-Plaid)

        /// GET (list) / POST (create) for the caller's manual accounts.
        static let manualAccounts = "/bank/manual-accounts"

        /// PATCH / DELETE on a specific manual account by id.
        static func manualAccount(_ id: String) -> String {
            "/bank/manual-accounts/\(id)"
        }
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

        /// GET list · PUT/GET/DELETE `/{id}` — the Agent tab's saved
        /// conversations, stored per user on the server.
        static let conversations = "/agent/conversations"

        /// POST — admin-only. Clears the Redis voice-minute counter
        /// for the authenticated user. Used by the temporary
        /// "Reset Voice Minutes" debug button in Settings.
        static let resetMinutes = "/agent/admin/reset-minutes"
    }

    // MARK: - Preferences

    enum Preferences {
        static let get = "/users/preferences"
        static let update = "/users/preferences"
        static let voices = "/users/voices"
        static let aiConsent = "/users/preferences/ai-consent"
    }

    // MARK: - Legal
    enum Legal {
        static let terms = "/legal/terms"
        static let privacy = "/legal/privacy"
    }

    // MARK: - SSI

    enum SSI {
        /// GET — BWE/IRWE candidates the classifier spotted this month.
        static let candidates = "/ssi/exclusions/candidates"

        /// GET — confirmed SSI deductions for the current month.
        static let exclusions = "/ssi/exclusions"

        /// POST — confirm a transaction as a BWE/IRWE/burial deduction.
        static let createExclusion = "/ssi/exclusions"

        /// DELETE — undo a previously confirmed deduction.
        static func deleteExclusion(_ exclusionId: String) -> String {
            "/ssi/exclusions/\(exclusionId)"
        }

        /// GET — voice/UI-entered manual deductions for the current month.
        static let manualDeductions = "/ssi/manual-deductions"

        /// POST — log a manual deduction.
        static let createManualDeduction = "/ssi/manual-deductions"

        /// DELETE — remove a manual deduction.
        static func deleteManualDeduction(_ deductionId: String) -> String {
            "/ssi/manual-deductions/\(deductionId)"
        }

        /// PATCH — attach a receipt / change type / flag a counselor question.
        static func updateManualDeduction(_ deductionId: String) -> String {
            "/ssi/manual-deductions/\(deductionId)"
        }

        /// POST (multipart, field "file") — upload a receipt; returns asset_id.
        static let uploadReceipt = "/ssi/receipts"

        /// POST — server-side extraction fallback (Claude vision). Never saves.
        static func extractReceipt(_ assetId: String) -> String {
            "/ssi/receipts/\(assetId)/extract"
        }

        /// GET — short-lived signed URL to view a receipt.
        static func receiptURL(_ assetId: String) -> String {
            "/ssi/receipts/\(assetId)/url"
        }

        /// GET — expenses flagged "Not sure this counts? Ask my counselor".
        static let counselorQuestions = "/ssi/counselor-questions"

        /// GET — CSV export of SSI deductions for a period.
        /// Query: ?year=YYYY[&month=MM]. Omitting month exports the
        /// full year. Response is text/csv.
        static func exportDeductions(year: Int, month: Int?) -> String {
            if let m = month {
                return "/ssi/deductions/export?year=\(year)&month=\(m)"
            }
            return "/ssi/deductions/export?year=\(year)"
        }

        /// POST — same CSV as exportDeductions but emails it to the
        /// authenticated user's account address via Mailgun. Returns
        /// `{success, sent_to, period, row_count}`. Used by the
        /// "Email me the file" button on the Logged Deductions card.
        static func emailDeductions(year: Int, month: Int?) -> String {
            if let m = month {
                return "/ssi/deductions/email?year=\(year)&month=\(m)"
            }
            return "/ssi/deductions/email?year=\(year)"
        }

        // MARK: WP6 — reminders, monthly package, submission log

        /// GET — work-expense reminders + field-office guidance.
        static let reminders = "/ssi/reminders"

        /// GET — manual deductions / exclusions for an explicit month.
        static func manualDeductions(month: String) -> String { "/ssi/manual-deductions?month=\(month)" }
        static func exclusions(month: String) -> String { "/ssi/exclusions?month=\(month)" }

        /// PATCH — attach a receipt to a confirmed bank charge.
        static func updateExclusion(_ exclusionId: String) -> String { "/ssi/exclusions/\(exclusionId)" }

        /// GET — contents checklist + per-page text (no PDF render).
        static func packetSummary(month: String) -> String { "/ssi/packet/summary?month=\(month)" }
        /// GET — the SSA-795 package PDF bytes.
        static func packet(month: String) -> String { "/ssi/packet?month=\(month)" }
        /// POST — email the package to the user (never to SSA).
        static func emailPacket(month: String) -> String { "/ssi/packet/email?month=\(month)" }

        /// GET — submission history.
        static let submissions = "/ssi/submissions"
        /// POST — the user logs that they handed a month in / undoes it.
        static func markSubmitted(month: String) -> String { "/ssi/submissions/\(month)/mark" }
        static func unmarkSubmitted(month: String) -> String { "/ssi/submissions/\(month)/unmark" }
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
