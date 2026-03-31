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
            Text("Renews \(renewalText)")
              .font(.caption)
              .foregroundColor(.gray)
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

        // Actions
        VStack(spacing: 12) {
          Button {
            showingPaywall = true
          } label: {
            HStack(spacing: 16) {
              Image(systemName: "arrow.up.circle.fill")
                .foregroundColor(.purple)
                .font(.title3)
                .frame(width: 32)
                .accessibilityHidden(true)

              VStack(alignment: .leading, spacing: 4) {
                Text(subscriptionService.hasActiveSubscription ? "Change Plan" : "Subscribe")
                  .font(.headline)
                  .foregroundColor(.white)
                Text(subscriptionService.hasActiveSubscription ? "Upgrade or downgrade your plan" : "Choose a subscription plan")
                  .font(.subheadline)
                  .foregroundColor(.gray)
              }

              Spacer()

              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
            }
            .padding(16)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
          }
          .accessibilityElement(children: .combine)
          .accessibilityHint("Opens plan selection")

          if subscriptionService.hasActiveSubscription {
            Button {
              openSubscriptionManagement()
            } label: {
              HStack(spacing: 16) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundColor(.red)
                  .font(.title3)
                  .frame(width: 32)
                  .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                  Text("Cancel Subscription")
                    .font(.headline)
                    .foregroundColor(.white)
                  Text("Manage via Apple Settings")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                  .font(.caption)
                  .foregroundColor(.gray)
              }
              .padding(16)
              .background(Color.gray.opacity(0.1))
              .cornerRadius(16)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Apple subscription management")
          }
        }
      }
      .padding(.horizontal, 20)
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
