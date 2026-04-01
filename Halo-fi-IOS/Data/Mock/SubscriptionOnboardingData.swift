//
//  MockSubscriptionOnboardingData.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SubscriptionOnboardingData {
  
  /// Subscription benefit pages to show before subscription screen
  static let benefitPages: [OnboardingPage] = [
    OnboardingPage(
      title: "Voice-First Conversations",
      subtitle: "Talk naturally with your financial assistant",
      description: "Ask questions, get insights, and manage your finances through natural voice conversations. No typing required.",
      icon: "mic.circle.fill",
      color: [Color.purple, Color.indigo],
      showsLogo: true
    ),
    OnboardingPage(
      title: "Instant Account Updates",
      subtitle: "Real-time financial data",
      description: "Get instant account refreshes to see your latest transactions and balances without waiting.",
      icon: "arrow.clockwise.circle.fill",
      color: [Color.blue, Color.cyan]
    ),
    OnboardingPage(
      title: "AI-Powered Insights",
      subtitle: "Smart financial guidance",
      description: "Receive personalized recommendations and insights powered by advanced AI to help you make better financial decisions.",
      icon: "sparkles",
      color: [Color.orange, Color.pink]
    )
  ]
}
