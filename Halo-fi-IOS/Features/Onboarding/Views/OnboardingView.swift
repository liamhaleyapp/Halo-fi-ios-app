//
//  OnboardingView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct OnboardingView: View {
  @Environment(UserManager.self) private var userManager
  @Environment(PermissionManager.self) private var permissionManager
  @State private var currentPage = 0
  @State private var showingSignUp = false
  @State private var showingSignIn = false
  @State private var showingPermissionRequest = false
  /// Which auth screen the user asked for before the mic-permission
  /// detour. Used to route AFTER the permission screen — previously the
  /// router guessed from the carousel page, sending first-time users who
  /// tapped "Get Started" on an early page to Sign In instead of Sign Up.
  private enum AuthDestination { case signUp, signIn }
  @State private var pendingAuthDestination: AuthDestination = .signUp
  
  private let onboardingPages = OnboardingData.pages
  
  var body: some View {
    ZStack {
      // Background
      Color.haloBackground.ignoresSafeArea()
      
      VStack(spacing: 0) {
        // Page Content
        TabView(selection: $currentPage) {
          ForEach(0..<onboardingPages.count, id: \.self) { index in
            OnboardingPageView(page: onboardingPages[index])
              .tag(index)
          }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .animation(.easeInOut, value: currentPage)
        // Game-quality swipe haptic — pitch ramps as the user
        // approaches the last page so blind users feel where they
        // are in the carousel by feel alone. Pairs with the
        // existing visual page indicator. Edge-bounce isn't fired
        // here because PageTabView swallows past-end swipes; the
        // ascending tick at the final page is the "you're at the
        // end" signal on its own.
        .onChange(of: currentPage) { oldValue, newValue in
            guard oldValue != newValue, !onboardingPages.isEmpty else { return }
            let progress = Double(newValue) / Double(max(onboardingPages.count - 1, 1))
            Haptics.engine.play(.tickAscending(progress: progress))
        }
        
        // Bottom Section
        OnboardingBottomSection(
          currentPage: currentPage,
          totalPages: onboardingPages.count,
          onGetStarted: {
            pendingAuthDestination = .signUp
            if permissionManager.microphonePermission == .notDetermined {
              showingPermissionRequest = true
            } else {
              showingSignUp = true
            }
          },
          onSignIn: {
            pendingAuthDestination = .signIn
            if permissionManager.microphonePermission == .notDetermined {
              showingPermissionRequest = true
            } else {
              showingSignIn = true
            }
          }
        )
      }
      // Readable width is applied per-section (page text, CTA buttons)
      // rather than to the whole stack — capping the stack left the
      // bottom section's background inset from the screen edges on iPad,
      // which read as a clipped floating panel.
    }
    .navigationBarHidden(true)
    .onAppear {
      // Returning users on this device skip the marketing carousel and go
      // straight to Sign In. They can dismiss back to see the carousel if
      // they want to (e.g., to tap "Sign Up" for a different account).
      if UserDefaults.standard.bool(forKey: "has_signed_in_before") && !showingSignIn {
        showingSignIn = true
      }
    }
    .fullScreenCover(isPresented: $showingSignUp) {
      SignUpView()
    }
    .fullScreenCover(isPresented: $showingSignIn) {
      SignInView()
    }
    .fullScreenCover(isPresented: $showingPermissionRequest) {
      PermissionRequestView(
        onContinue: {
          showingPermissionRequest = false
          // Onboarding proceeds regardless of the mic grant/deny outcome.
          // Route to the screen the user actually asked for — "Get
          // Started" → Sign Up, "I already have an account" → Sign In.
          switch pendingAuthDestination {
          case .signUp: showingSignUp = true
          case .signIn: showingSignIn = true
          }
        }
      )
    }
  }
}

#Preview {
  OnboardingView()
}
