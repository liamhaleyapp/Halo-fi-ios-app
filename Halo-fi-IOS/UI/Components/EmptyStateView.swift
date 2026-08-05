//
//  EmptyStateView.swift
//  Halo-fi-IOS
//
//  Reusable empty state component for displaying when no data is available.
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)?
    // Scales with Dynamic Type (App Store Guideline 4).
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48
    var actionTitle: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundColor(.haloTextPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(actionTitle)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

// MARK: - Compact Variant

extension EmptyStateView {
    /// A compact empty state with just a message, no icon or title
    static func compact(_ message: String) -> some View {
        HStack {
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityLabel(message)
    }
}

// MARK: - Previews

#Preview("With Action Button") {
    ZStack {
        Color.haloBackground.ignoresSafeArea()
        EmptyStateView(
            icon: "building.2",
            title: "No Accounts Linked",
            message: "Connect your bank accounts to get started",
            action: { },
            actionTitle: "Link Account"
        )
        .padding()
    }
}

#Preview("Without Action Button") {
    ZStack {
        Color.haloBackground.ignoresSafeArea()
        EmptyStateView(
            icon: "creditcard",
            title: "No Accounts Found",
            message: "No accounts were found for this institution"
        )
        .padding()
    }
}

#Preview("Compact") {
    ZStack {
        Color.haloBackground.ignoresSafeArea()
        EmptyStateView.compact("No accounts found")
            .padding()
    }
}
