//
//  PostLoginSplashView.swift
//  Halo-fi-IOS
//
//  Created by Claude on 12/27/25.
//

import SwiftUI

/// Loading view displayed after login while fetching account data
/// to determine if user should see onboarding or main app
struct PostLoginSplashView: View {
    var error: String? = nil
    var onRetry: (() -> Void)? = nil
    var body: some View {
        ZStack {
            Color.haloBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                if error == nil { ProgressView()
                    .scaleEffect(1.5)
                    .tint(.haloTextPrimary) }

                Text(error ?? "Loading your account…")
                    .font(.headline)
                    .foregroundColor(.haloTextSecondary)
                if error != nil, let onRetry {
                    Button("Try again", action: onRetry).frame(minHeight: 44)
                }
            }
            .padding(24)
        }
    }
}

#Preview {
    PostLoginSplashView()
}
