//
//  DesignTokens.swift
//  Halo-fi-IOS
//
//  Centralized color and gradient tokens. Phase 2-7 of the SSI
//  rules-engine rebuild reads from here so new cards (earn-room,
//  BWE/IRWE confirmation sheet, §1619(b) banner, ABLE settings row)
//  stay visually consistent with the existing SSI hero cards.
//
//  When refactoring BudgetView's inline `Color(red:...)` values,
//  swap them for the matching token below — every value here is
//  taken verbatim from the existing inline usages so the visual
//  output is byte-for-byte identical.
//

import SwiftUI

enum DesignTokens {

    // MARK: - SSI hero cards

    enum SSI {
        /// Navy gradient used by every SSI hero card background.
        /// Source: BudgetView.swift inline gradient at the resource /
        /// income / next-deposit cards.
        static let heroGradientColors: [Color] = [
            Color(red: 0.16, green: 0.22, blue: 0.48),
            Color(red: 0.10, green: 0.14, blue: 0.32),
        ]

        static var heroGradient: LinearGradient {
            LinearGradient(
                colors: heroGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        // MARK: Subtext on navy background
        // The existing cards use white at 0.75 / 0.70 opacity. The
        // `bright` token bumps to 0.92 for any text that needs
        // higher contrast on the navy gradient (the user flagged the
        // current shade as too dim for comfortable reading).
        static let subtextPrimary: Color = .white.opacity(0.75)
        static let subtextSecondary: Color = .white.opacity(0.70)
        static let subtextBright: Color = .white.opacity(0.92)

        // MARK: Status chip colors (over / warning / safe)
        // Solid status colors — used as foreground on the hero card
        // body and in alert banners.
        static let statusOver: Color = Color(red: 1.00, green: 0.45, blue: 0.35)
        static let statusWarning: Color = Color(red: 1.00, green: 0.65, blue: 0.25)
        static let statusSafe: Color = Color(red: 0.40, green: 0.85, blue: 0.55)
        static let statusBehind: Color = Color(red: 1.00, green: 0.65, blue: 0.25)
        static let statusAhead: Color = Color(red: 0.40, green: 0.85, blue: 0.55)
        static let statusNeutral: Color = Color(red: 0.95, green: 0.80, blue: 0.35)

        // Status chip background (status color at 30% opacity on navy).
        static let chipBgOver: Color = statusOver.opacity(0.30)
        static let chipBgWarning: Color = statusWarning.opacity(0.30)
        static let chipBgSafe: Color = statusSafe.opacity(0.30)
        static let chipBgNeutral: Color = .white.opacity(0.20)

        // Status chip foreground (lighter shade for readable text on chip bg).
        static let chipFgOver: Color = Color(red: 1.00, green: 0.78, blue: 0.72)
        static let chipFgWarning: Color = Color(red: 1.00, green: 0.86, blue: 0.62)
        static let chipFgSafe: Color = Color(red: 0.74, green: 0.96, blue: 0.81)

        // Generic translucent fill used for progress-bar tracks and pill
        // backgrounds that overlay the navy gradient.
        static let translucentFill: Color = .white.opacity(0.22)
        static let translucentFillSubtle: Color = .white.opacity(0.18)
    }
}
