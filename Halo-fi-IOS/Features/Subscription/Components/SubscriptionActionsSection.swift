//
//  SubscriptionActionsSection.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/1/25.
//

import SwiftUI

struct SubscriptionActionButtonsSection: View {
  
  let hasActiveSubscription: Bool
  let isOnboarding: Bool
  let isBusy: Bool
  let selectedPlanName: String
  let onContinue: (() -> Void)?
  let onSubscribe: () -> Void
  let onChangePlan: () -> Void
  let onRestore: () -> Void
  let onUpdatePayment: () -> Void
  let onCancelSubscription: () -> Void
  
  var body: some View {
    VStack(spacing: 12) {
      // Subscribe button if no active subscription, otherwise show change plan
      if hasActiveSubscription {
        // In onboarding mode, show Continue button first, then Change Plan
        if isOnboarding {
          continueButton
          changePlanButton
          updatePaymentButton
        } else {
          // Regular mode: show Change Plan, Update Payment, Cancel
          changePlanButton
          updatePaymentButton
          cancelSubscriptionButton
        }
      } else {
        subscribeButton
        restorePurchasesButton
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 40)
    .disabled(isBusy)
  }
  
  // MARK: - Continue Button (Onboarding)
  private var continueButton: some View {
    Button {
      onContinue?()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "checkmark.circle.fill")
          .font(.headline)
          .foregroundColor(.white)
        
        Text("Continue")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(
        LinearGradient(
          colors: [Color.green, Color.green.opacity(0.8)],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .cornerRadius(12)
    }
  }
  
  // MARK: - Subscribe Button
  private var subscribeButton: some View {
    Button(action: onSubscribe) {
      HStack(spacing: 12) {
        Image(systemName: "star.fill")
          .font(.headline)
          .foregroundColor(.white)
        
        Text("Subscribe to \(selectedPlanName)")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(
        LinearGradient(
          colors: [Color.indigo, Color.purple],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .cornerRadius(12)
    }
  }
  
  // MARK: - Restore Purchases Button
  private var restorePurchasesButton: some View {
    Button(action: onRestore) {
      HStack(spacing: 12) {
        Image(systemName: "arrow.clockwise.circle.fill")
          .font(.headline)
          .foregroundColor(.white)
        
        Text("Restore Purchases")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(
        LinearGradient(
          colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.5)],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .cornerRadius(12)
    }
  }
  
  // MARK: - Change Plan Button
  private var changePlanButton: some View {
    Button(action: onChangePlan) {
      HStack(spacing: 12) {
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.headline)
          .foregroundColor(.white)
        
        Text("Change Plan")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(
        LinearGradient(
          colors: [Color.teal, Color.blue],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .cornerRadius(12)
    }
  }
  
  // MARK: - Update Payment Button
  private var updatePaymentButton: some View {
    Button(action: onUpdatePayment) {
      HStack(spacing: 12) {
        Image(systemName: "creditcard.fill")
          .font(.headline)
          .foregroundColor(.white)
        
        Text("Update Payment Method")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(
        LinearGradient(
          colors: [Color.teal.opacity(0.8), Color.cyan],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .cornerRadius(12)
    }
  }
  
  // MARK: - Cancel Subscription Button
  private var cancelSubscriptionButton: some View {
    Button(action: onCancelSubscription) {
      HStack(spacing: 12) {
        Image(systemName: "xmark.circle.fill")
          .font(.headline)
          .foregroundColor(.white)
        
        Text("Cancel Subscription")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(
        LinearGradient(
          colors: [Color.white.opacity(0.9), Color.gray.opacity(0.7)],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .cornerRadius(12)
    }
  }
}
