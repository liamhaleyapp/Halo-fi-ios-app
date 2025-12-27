//
//  AppEnvironment.swift
//  Halo-fi-IOS
//
//  Build environment configuration for multi-environment support.
//  Supports Debug, TestFlight (Sandbox/Prod), and App Store builds.
//

import Foundation

// MARK: - Build Configuration Guards

// Compile-time safety: DIRECT_LINK_BYPASS can only be used with SANDBOX
// This prevents accidentally shipping bypass code in production builds
#if DIRECT_LINK_BYPASS && !SANDBOX
#error("DIRECT_LINK_BYPASS requires SANDBOX. Remove DIRECT_LINK_BYPASS or add SANDBOX.")
#endif

// Warning for sandbox without direct mode (Link UI will hit prod endpoint unless backend supports sandbox link)
#if SANDBOX && !DIRECT_LINK_BYPASS
#warning("SANDBOX build without DIRECT_LINK_BYPASS: Link UI will use production endpoint unless backend supports sandbox link.")
#endif

/// Build environment configuration
struct AppEnvironment {

    // MARK: - Plaid Environment

    enum PlaidEnv {
        case sandbox
        case production
    }

    /// Plaid environment based on SANDBOX flag
    /// Production is default when SANDBOX isn't defined
    static let plaidEnv: PlaidEnv = {
        #if SANDBOX
        return .sandbox
        #else
        return .production
        #endif
    }()

    // MARK: - Link Flow Mode

    enum LinkMode {
        case linkUI         // Standard Plaid Link flow
        case directCreate   // Bypass Link UI (sandbox testing shortcut)
    }

    /// Link flow mode based on DIRECT_LINK_BYPASS flag
    static let linkMode: LinkMode = {
        #if DIRECT_LINK_BYPASS
        return .directCreate
        #else
        return .linkUI
        #endif
    }()

    // MARK: - Build Type Detection

    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var isTestFlight: Bool {
        #if TESTFLIGHT
        return true
        #else
        return false
        #endif
    }

    /// True only for App Store builds (not Debug, not TestFlight)
    static var isAppStoreBuild: Bool {
        !isDebug && !isTestFlight
    }

    /// True when using production Plaid (TF-Prod or App Store)
    static var isProdPlaid: Bool {
        plaidEnv == .production
    }

    // MARK: - Debug Info

    /// Returns a descriptive string with emoji for easy QA identification
    /// Examples:
    /// - "🚧 Debug • Sandbox • Direct"
    /// - "🧪 TestFlight • Sandbox • Direct"
    /// - "⚠️ TestFlight • Prod"
    /// - "✅ App Store • Prod"
    static var buildTypeDescription: String {
        var parts: [String] = []

        // Build type with emoji
        if isDebug {
            parts.append("🚧 Debug")
        } else if isTestFlight {
            parts.append(isProdPlaid ? "⚠️ TestFlight" : "🧪 TestFlight")
        } else {
            parts.append("✅ App Store")
        }

        // Plaid environment
        switch plaidEnv {
        case .sandbox: parts.append("Sandbox")
        case .production: parts.append("Prod")
        }

        // Link mode (only show if using direct create)
        if linkMode == .directCreate {
            parts.append("Direct")
        }

        return parts.joined(separator: " • ")
    }
}
