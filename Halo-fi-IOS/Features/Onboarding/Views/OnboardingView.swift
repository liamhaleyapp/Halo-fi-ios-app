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
  
  private let onboardingPages = OnboardingData.pages
  
  var body: some View {
    ZStack {
      // Background
      Color.black.ignoresSafeArea()
      
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
        
        // Bottom Section
        OnboardingBottomSection(
          currentPage: currentPage,
          totalPages: onboardingPages.count,
          onGetStarted: { 
            if permissionManager.microphonePermission == .notDetermined {
              showingPermissionRequest = true
            } else {
              showingSignUp = true
            }
          },
          onSignIn: { 
            if permissionManager.microphonePermission == .notDetermined {
              showingPermissionRequest = true
            } else {
              showingSignIn = true
            }
          }
        )
      }
    }
    .navigationBarHidden(true)
    .fullScreenCover(isPresented: $showingSignUp) {
      SignUpView()
    }
    .fullScreenCover(isPresented: $showingSignIn) {
      SignInView()
    }
    .fullScreenCover(isPresented: $showingPermissionRequest) {
      PermissionRequestView(
        onPermissionGranted: {
          showingPermissionRequest = false
          // Continue to sign up/sign in based on what was originally requested
          if currentPage == onboardingPages.count - 1 {
            showingSignUp = true
          } else {
            showingSignIn = true
          }
        },
        onSkip: {
          showingPermissionRequest = false
          // Allow user to continue without permission
          if currentPage == onboardingPages.count - 1 {
            showingSignUp = true
          } else {
            showingSignIn = true
          }
        }
      )
    }
  }
}

#Preview {
  OnboardingView()
}
