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
    let onSignIn: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Page Indicators
            PageIndicator(currentPage: currentPage, totalPages: totalPages)
            
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
                
                // Sign In Button
                Button(action: onSignIn) {
                    Text("I already have an account")
                        .font(.body)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingBottomSection(
            currentPage: 1,
            totalPages: 3,
            onGetStarted: {},
            onSignIn: {}
        )
    }
}
