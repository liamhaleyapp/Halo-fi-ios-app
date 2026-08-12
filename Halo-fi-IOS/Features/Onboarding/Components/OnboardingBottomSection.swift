//
//  OnboardingBottomSection.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Onboarding Bottom Section Component
struct OnboardingBottomSection: View {
    let currentPage: Int
    let totalPages: Int
    let onGetStarted: () -> Void
    let onSignIn: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 24) {
            // Page Indicators
            PageIndicator(currentPage: currentPage, totalPages: totalPages)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(currentPage + 1) of \(totalPages)")
            
            // Action Buttons
            VStack(spacing: 16) {
                // Get Started Button
                ActionButton(
                    title: "Get Started",
                    gradient: LinearGradient(
                        colors: [Color.purple, Color.indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                ) {
                    onGetStarted()
                }
                
                // Sign In Button (only show if handler is provided)
                if let onSignIn = onSignIn {
                    Button(action: onSignIn) {
                        Text("I already have an account")
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("Sign in")
                    .accessibilityHint("Double-tap if you already have an account")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            // Buttons stay readable-width on iPad; the scrim behind them
            // still spans the full screen (see .frame below).
            .readableContentWidth()
        }
        // Was a hardcoded black gradient from the dark-only era, which
        // drew as a floating black slab on the light-mode white
        // background. Fading the screen background into itself keeps the
        // original "carousel fades out under the CTA" intent and is
        // invisible in both themes.
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.haloBackground.opacity(0), Color.haloBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.haloBackground.ignoresSafeArea()
        OnboardingBottomSection(
            currentPage: 1,
            totalPages: 3,
            onGetStarted: {},
            onSignIn: {}
        )
    }
}
