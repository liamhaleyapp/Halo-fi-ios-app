//
//  OnboardingView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct OnboardingView: View {
  @Environment(UserManager.self) private var userManager
  @State private var currentPage = 0
  @State private var showingSignUp = false
  @State private var showingSignIn = false
  
  private let onboardingPages = MockOnboardingData.pages
  
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
          onGetStarted: { showingSignUp = true },
          onSignIn: { showingSignIn = true }
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
  }
}

#Preview {
  OnboardingView()
}
