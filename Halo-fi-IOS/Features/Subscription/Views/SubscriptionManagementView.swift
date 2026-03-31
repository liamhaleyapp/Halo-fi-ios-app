//
//  SubscriptionManagementView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 3/31/26.
//

import SwiftUI
import RevenueCatUI

struct SubscriptionManagementView: View {
  @Environment(SubscriptionService.self) private var subscriptionService
  @State private var showingPaywall = false

  private var renewalText: String {
    guard let date = subscriptionService.renewalDate else {
      return "N/A"
    }
    return date.formatted(date: .long, time: .omitted)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        // Current Plan
        HStack(spacing: 16) {
          Image(systemName: "crown.fill")
            .foregroundColor(.purple)
            .font(.title3)
            .frame(width: 32)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 4) {
            Text("Current Plan")
              .font(.subheadline)
              .foregroundColor(.gray)
            Text(subscriptionService.currentSubscription.displayName)
              .font(.headline)
              .foregroundColor(.white)
          }

          Spacer()

          if subscriptionService.hasActiveSubscription {
            VStack(alignment: .trailing, spacing: 4) {
              if let pending = subscriptionService.pendingPlanChange {
                Text("Switching to \(pending)")
                  .font(.caption)
                  .foregroundColor(.orange)
                Text("on \(renewalText)")
                  .font(.caption)
                  .foregroundColor(.gray)
              } else {
                Text("Renews \(renewalText)")
                  .font(.caption)
                  .foregroundColor(.gray)
              }
            }
          } else {
            Text("Inactive")
              .font(.caption)
              .foregroundColor(.red)
          }
        }
        .padding(16)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
        .accessibilityElement(children: .combine)

        // Primary Action
        ActionButton(
          title: subscriptionService.hasActiveSubscription ? "Change Plan" : "Subscribe Now",
          gradient: LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
          )
        ) {
          showingPaywall = true
        }
        .padding(.top, 8)

        // Cancel — de-emphasized text link
        if subscriptionService.hasActiveSubscription {
          Button {
            openSubscriptionManagement()
          } label: {
            Text("Cancel Subscription")
              .font(.subheadline)
              .foregroundColor(.gray)
          }
          .padding(.top, 16)
          .accessibilityHint("Opens Apple subscription management")
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 100)
    }
    .background(Color.black.ignoresSafeArea())
    .navigationTitle("Subscription")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showingPaywall) {
      PaywallView()
        .onPurchaseCompleted { _ in
          Task { await subscriptionService.checkSubscriptionStatus() }
          showingPaywall = false
        }
        .onRestoreCompleted { _ in
          Task { await subscriptionService.checkSubscriptionStatus() }
        }
    }
    .onAppear {
      Task { await subscriptionService.checkSubscriptionStatus() }
    }
  }

  private func openSubscriptionManagement() {
    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
      UIApplication.shared.open(url)
    }
  }
}

#Preview {
  NavigationStack {
    SubscriptionManagementView()
      .environment(SubscriptionService.previewActivePro)
  }
}
