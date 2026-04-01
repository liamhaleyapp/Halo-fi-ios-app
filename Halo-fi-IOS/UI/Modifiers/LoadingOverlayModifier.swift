//
//  LoadingOverlayModifier.swift
//  Halo-fi-IOS
//
//  Reusable loading overlay modifier for blocking operations.
//  Use for auth, destructive actions, or any "can't interact right now" moments.
//  For normal list refreshes or small fetches, use inline loading (ProgressView, skeletons) instead.
//

import SwiftUI

struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    let message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(!isLoading)
                .accessibilityHidden(isLoading)

            if isLoading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                    .transition(.opacity)
                    .zIndex(1)

                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(message ?? "Loading")
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isLoading)
    }
}

extension View {
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading, message: message))
    }
}

#Preview("Not Loading") {
    Text("Content here")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blue)
        .loadingOverlay(isLoading: false)
}

#Preview("Loading") {
    Text("Content here")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blue)
        .loadingOverlay(isLoading: true, message: "Please wait...")
}
