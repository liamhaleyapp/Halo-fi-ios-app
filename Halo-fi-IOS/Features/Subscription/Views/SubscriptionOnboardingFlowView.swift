//
//  SubscriptionOnboardingFlowView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SubscriptionOnboardingFlowView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(SubscriptionService.self) private var subscriptionService
  @Environment(UserManager.self) private var userManager
  var onComplete: (() -> Void)?
  var hideBackButton: Bool = false
  @State private var currentPage = 0
  @State private var showingSubscriptionView = false
  @State private var showingPlaidOnboarding = false
  
  private let benefitPages = SubscriptionOnboardingData.benefitPages
  private let totalBenefitPages: Int
  
  init(onComplete: (() -> Void)? = nil, hideBackButton: Bool = false) {
    self.onComplete = onComplete
    self.hideBackButton = hideBackButton
    totalBenefitPages = SubscriptionOnboardingData.benefitPages.count
  }
  
  var body: some View {
    NavigationStack {
      ZStack {
        Color.haloBackground.ignoresSafeArea()
        
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
                    .foregroundColor(.haloTextPrimary)
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
            // Game-quality swipe haptic — pitch ramps as the user
            // approaches the last benefit page so blind users feel
            // their position in the carousel without needing to count
            // dots they can't see. Each tick gets brighter as
            // progress approaches 1.0.
            .onChange(of: currentPage) { oldValue, newValue in
                guard oldValue != newValue, totalBenefitPages > 0 else { return }
                let progress = Double(newValue) / Double(max(totalBenefitPages - 1, 1))
                Haptics.engine.play(.tickAscending(progress: progress))
            }
            
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
        }
      }
      .navigationBarHidden(true)
    }
    .navigationDestination(isPresented: $showingPlaidOnboarding) {
      PlaidOnboardingView(
        onComplete: { showingPlaidOnboarding = false },
        onBack: { showingPlaidOnboarding = false },
        isOnboarding: true
      )
      .navigationBarTitleDisplayMode(.inline)
    }
    .fullScreenCover(isPresented: $showingSubscriptionView) {
      AccountSubscriptionPaywall(displayCloseButton: false) {
        showingSubscriptionView = false
        if let onComplete {
          onComplete()
        } else {
          showingPlaidOnboarding = true
        }
      }
    }

    .accessibilityElement(children: .contain)
    .accessibilityLabel("Connect Bank")
    .accessibilityHint("Step 3 of 3 in the setup process")
  }
}

/// Terms of Use (EULA) + Privacy Policy links shown inside the subscription
/// purchase flow. Required by App Store Guideline 3.1.2(c). Reused by both
/// the onboarding paywall and the subscription-management paywall.
struct SubscriptionLegalLinks: View {
  private let termsURL = URL(string: "https://halofiapp.com/terms")!
  private let privacyURL = URL(string: "https://halofiapp.com/privacy")!

  var body: some View {
    VStack(spacing: 8) {
      Link(destination: termsURL) { SubscriptionActionLabel("Terms of Use") }
      Link(destination: privacyURL) { SubscriptionActionLabel("Privacy Policy") }
    }
    .font(.body)
    .tint(Color.primary)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(.thinMaterial)
    .accessibilityElement(children: .contain)
  }
}

#Preview {
  SubscriptionOnboardingFlowView()
    .environment(SubscriptionService())
    .environment(UserManager())
}
