//
//  OnboardingPageView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Onboarding Page View Component
struct OnboardingPageView: View {
    // Scales with Dynamic Type (App Store Guideline 4).
    @ScaledMetric(relativeTo: .largeTitle) private var pageIconSize: CGFloat = 60
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let page: OnboardingPage

    var body: some View {
        // At accessibility sizes the wrapped title and subtitle outgrow the
        // page (2026-09-29: "Voice-First Conversations" truncated); scroll
        // instead of clipping.
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView { content }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            if page.showsLogo {
                HaloFiLogo(size: 120)
            } else {
                Circle()
                    .fill(LinearGradient(colors: page.color, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: page.icon)
                            .font(.system(size: pageIconSize))
                            .foregroundColor(.white)
                    )
                    .accessibilityHidden(true)
            }

            // Text Content — every line wraps; nothing truncates or shrinks.
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.haloTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(page.subtitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.description)
                    .font(.body)
                    .foregroundColor(.haloTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(.horizontal, 20)
        .readableContentWidth()
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.haloBackground.ignoresSafeArea()
        OnboardingPageView(page: OnboardingData.pages[0])
    }
}
