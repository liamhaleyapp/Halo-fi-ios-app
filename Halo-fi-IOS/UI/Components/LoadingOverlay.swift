//
//  LoadingOverlay.swift
//  Halo-fi-IOS
//
//  Reusable loading overlay component.
//

import SwiftUI

struct LoadingOverlay: View {
    let title: String
    let subtitle: String
    var style: Style = .system

    enum Style {
        case system   // Uses system colors on system background
        case gradient // White text on gradient background

        var textColor: Color {
            switch self {
            case .system: return .primary
            case .gradient: return .white
            }
        }

        var subtitleColor: Color {
            switch self {
            case .system: return .secondary
            case .gradient: return .white.opacity(0.7)
            }
        }

        var progressTint: Color {
            switch self {
            case .system: return .accentColor
            case .gradient: return .white
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(style.progressTint)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(style.textColor)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(style.subtitleColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundView)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .system:
            Color(.systemBackground)
        case .gradient:
            LinearGradient(
                colors: [Color.indigo, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Convenience Initializers

extension LoadingOverlay {
    /// Default loading overlay with "Setting up secure connection..." message
    static var secureConnection: LoadingOverlay {
        LoadingOverlay(
            title: "Setting up secure connection...",
            subtitle: "This may take a few moments"
        )
    }

    /// Gradient loading overlay with "Setting up secure connection..." message
    static var secureConnectionGradient: LoadingOverlay {
        LoadingOverlay(
            title: "Setting up secure connection...",
            subtitle: "This may take a few moments",
            style: .gradient
        )
    }
}

// MARK: - Previews

#Preview("System Style") {
    LoadingOverlay.secureConnection
}

#Preview("Gradient Style") {
    LoadingOverlay.secureConnectionGradient
}

#Preview("Custom Message") {
    LoadingOverlay(
        title: "Loading your accounts...",
        subtitle: "Please wait",
        style: .gradient
    )
}
