//
//  SubscriptionOnboardingFlowView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
import RevenueCatUI

struct SubscriptionOnboardingFlowView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(SubscriptionService.self) private var subscriptionService
  @Environment(UserManager.self) private var userManager
  var onComplete: (() -> Void)?
  var hideBackButton: Bool = false
  @State private var currentPage = 0
  @State private var showingSubscriptionView = false
  @State private var showingPlaidOnboarding = false
  
  private let benefitPages = MockSubscriptionOnboardingData.benefitPages
  private let totalBenefitPages: Int
  
  init(onComplete: (() -> Void)? = nil, hideBackButton: Bool = false) {
    self.onComplete = onComplete
    self.hideBackButton = hideBackButton
    totalBenefitPages = MockSubscriptionOnboardingData.benefitPages.count
  }
  
  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()
        
        // Show benefit slides first
        if !showingSubscriptionView {
          VStack(spacing: 0) {
            // Back button in top-left - only show if not hidden
            if !hideBackButton {
              HStack {
                Button(action: {
                  if currentPage > 0 {
                    withAnimation {
                      currentPage -= 1
                    }
                  } else {
                    dismiss()
                  }
                }) {
                  Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
                }
                
                Spacer()
              }
              .padding(.horizontal, 20)
              .padding(.top, 10)
            }
            
            // Page Content
            TabView(selection: $currentPage) {
              ForEach(0..<benefitPages.count, id: \.self) { index in
                OnboardingPageView(page: benefitPages[index])
                  .tag(index)
              }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)
            
            // Bottom Section with navigation
            OnboardingBottomSection(
              currentPage: currentPage,
              totalPages: totalBenefitPages,
              onGetStarted: {
                // Move to subscription view
                withAnimation {
                  showingSubscriptionView = true
                }
              },
              onSignIn: nil // Not used in subscription flow
            )
          }
        } else {
          // Show RevenueCat paywall
          PaywallView(displayCloseButton: false)
            .onPurchaseCompleted { _ in
              Task {
                await subscriptionService.checkSubscriptionStatus()
              }
              if let onComplete = onComplete {
                onComplete()
              } else {
                showingPlaidOnboarding = true
              }
            }
            .onRestoreCompleted { _ in
              Task {
                await subscriptionService.checkSubscriptionStatus()
              }
              if subscriptionService.hasActiveSubscription {
                if let onComplete = onComplete {
                  onComplete()
                } else {
                  showingPlaidOnboarding = true
                }
              }
            }
            .overlay(alignment: .topLeading) {
              if !hideBackButton {
                Button(action: {
                  withAnimation {
                    showingSubscriptionView = false
                  }
                }) {
                  Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 15)
              }
            }
        }
      }
      .navigationBarHidden(true)
    }
    .onChange(of: subscriptionService.hasActiveSubscription) { _, newValue in
      // Automatically proceed to next step when subscription becomes active
      if newValue && showingSubscriptionView {
        Task {
          // Small delay to ensure subscription status is fully updated
          try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
          await MainActor.run {
            // Call completion handler if provided (for unified onboarding flow)
            // Otherwise show Plaid onboarding
            if let onComplete = onComplete {
              onComplete()
            } else {
              showingPlaidOnboarding = true
            }
          }
        }
      }
    }
    .navigationDestination(isPresented: $showingPlaidOnboarding) {
      PlaidOnboardingView(
        onComplete: { showingPlaidOnboarding = false },
        onBack: { showingPlaidOnboarding = false },
        isOnboarding: true
      )
      .navigationBarTitleDisplayMode(.inline)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Connect Bank")
    .accessibilityHint("Step 3 of 3 in the setup process")
  }
}

#Preview {
  SubscriptionOnboardingFlowView()
    .environment(SubscriptionService())
    .environment(UserManager())
}
