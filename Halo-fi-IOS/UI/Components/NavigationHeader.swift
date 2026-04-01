//
//  NavigationHeader.swift
//  Halo-fi-IOS
//
//  Reusable navigation header with back button and centered title.
//

import SwiftUI

struct NavigationHeader: View {
    let title: String
    let onBack: () -> Void
    var style: Style = .dark

    enum Style {
        case dark   // White text on dark background
        case light  // Primary text on light background

        var textColor: Color {
            switch self {
            case .dark: return .white
            case .light: return .primary
            }
        }

        var buttonBackground: Color {
            switch self {
            case .dark: return Color.gray.opacity(0.2)
            case .light: return Color(.quaternarySystemFill)
            }
        }
    }

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(style.textColor)
                    .frame(width: 40, height: 40)
                    .background(style.buttonBackground)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Back")

            Spacer()

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(style.textColor)

            Spacer()

            // Invisible spacer to center the title
            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }
}

// MARK: - Previews

#Preview("Dark Style") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            NavigationHeader(title: "Profile", onBack: {}, style: .dark)
            Spacer()
        }
    }
}

#Preview("Light Style") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        VStack {
            NavigationHeader(title: "Preferences", onBack: {}, style: .light)
            Spacer()
        }
    }
}
