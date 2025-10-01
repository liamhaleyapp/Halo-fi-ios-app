//
//  MockOnboardingData.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct MockOnboardingData {
  
  /// Sample onboarding pages
  static let pages: [OnboardingPage] = [
    OnboardingPage(
      title: "Welcome to Halo Fi",
      subtitle: "Your voice-first financial assistant",
      description: "Get personalized financial guidance through natural conversations. No more complex menus or confusing interfaces.",
      icon: "mic.circle.fill",
      color: [Color.purple, Color.indigo]
    ),
    OnboardingPage(
      title: "Smart Financial Insights",
      subtitle: "Powered by AI & Plaid",
      description: "Connect your accounts securely and get real-time insights about your spending, saving, and financial health.",
      icon: "brain.head.profile",
      color: [Color.blue, Color.teal]
    ),
    OnboardingPage(
      title: "Accessible for Everyone",
      subtitle: "Built with inclusivity in mind",
      description: "Designed specifically for the visually impaired community, with voice-first navigation and high-contrast interfaces.",
      icon: "eye.slash.fill",
      color: [Color.orange, Color.red]
    )
  ]
}
