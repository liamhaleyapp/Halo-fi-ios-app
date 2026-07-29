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
    var body: some View {
        ZStack {
            Color.haloBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.haloTextPrimary)

                Text("Setting up your experience...")
                    .font(.headline)
                    .foregroundColor(.haloTextSecondary)
            }
        }
    }
}

#Preview {
    PostLoginSplashView()
}
