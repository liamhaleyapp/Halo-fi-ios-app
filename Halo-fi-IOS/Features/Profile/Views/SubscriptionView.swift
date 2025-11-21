//
//  SubscriptionView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SubscriptionView: View {
  @Environment(\.dismiss) private var dismiss
  
  @State private var viewModel: SubscriptionViewModel
  var isOnboarding: Bool
  var onContinue: (() -> Void)?
  
  // Custom initializer
  init(
    isOnboarding: Bool = false,
    onContinue: (() -> Void)? = nil,
    viewModel: SubscriptionViewModel
  ) {
    self.isOnboarding = isOnboarding
    self.onContinue = onContinue
    _viewModel = State(initialValue: viewModel)
  }
  
  // MARK: - UI State
  @State private var showingChangePlan = false
  @State private var showingPaymentMethod = false
  @State private var showingCancelConfirmation = false
  @State private var showingPurchaseAlert = false
  @State private var showingRestoreAlert = false
  
  var body: some View {
    NavigationStack {
      ZStack {
        // Background
        Color.black.ignoresSafeArea()
        
        ScrollView {
          VStack(spacing: 16) {
            currentPlanSection
            planOptionsSection
            billingCycleSection
            actionButtonsSection
          }
        }
        
        // Loading overlay
        if viewModel.isLoadingPurchase || viewModel.isServiceLoading {
          Color.black.opacity(0.7)
            .ignoresSafeArea()
          
          VStack(spacing: 16) {
            ProgressView()
              .scaleEffect(1.5)
              .tint(.white)
            Text("Processing...")
              .foregroundColor(.white)
              .font(.subheadline)
          }
        }
      }
      .navigationTitle(isOnboarding ? "" : "Subscription")
      .navigationBarTitleDisplayMode(.large)
      .toolbarBackground(Color.black, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .navigationBarHidden(isOnboarding)
    }
    .task {
      await viewModel.onAppear()
    }
    .alert("Purchase", isPresented: $showingPurchaseAlert) {
      Button("OK", role: .cancel) { }
    } message: {
      Text(viewModel.purchaseAlertMessage)
    }
    .alert("Restore Purchases", isPresented: $showingRestoreAlert) {
      Button("OK", role: .cancel) { }
    } message: {
      Text(viewModel.restoreAlertMessage)
    }
    .alert("Change Plan", isPresented: $showingChangePlan) {
      Button("Cancel", role: .cancel) { }
      Button("Change", role: .destructive) {
        Task {
          let result = await viewModel.handlePurchase()
          switch result {
          case .success, .pending, .productsNotReady, .failure:
            showingPurchaseAlert = true
          case .cancelled:
            break
          }
        }
      }
    } message: {
      Text("Plan change will take effect at your next billing cycle.")
    }
    .alert("Update Payment Method", isPresented: $showingPaymentMethod) {
      Button("OK") { }
    } message: {
      Text("You can update your payment method in Settings > Apple ID > Subscriptions or App Store.")
    }
    .alert("Cancel Subscription", isPresented: $showingCancelConfirmation) {
      Button("Cancel", role: .cancel) { }
      Button("Yes, Cancel", role: .destructive) {
        viewModel.handleCancelSubscription()
      }
    } message: {
      Text("Are you sure you want to cancel your subscription? You'll lose access to premium features at the end of your current billing period. You can also manage this in Settings > Apple ID > Subscriptions.")
    }
  }
  
  // MARK: - Current Plan Section
  private var currentPlanSection: some View {
    VStack(spacing: 12) {
      if viewModel.hasActiveSubscription {
        // Show subscription status message
        if isOnboarding {
          VStack(spacing: 8) {
            HStack {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
              
              Text("You're subscribed to \(viewModel.currentPlanName).")
                .font(.headline)
                .foregroundColor(.white)
              
              Spacer()
            }
            
            Text("You can continue with your current subscription or change your plan below.")
              .font(.subheadline)
              .foregroundColor(.gray)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        } else {
          HStack {
            Text("Current Plan")
              .font(.headline)
              .foregroundColor(.gray)
            
            Spacer()
            
            Text(viewModel.currentPlanName)
              .font(.title2)
              .fontWeight(.bold)
              .foregroundColor(.white)
          }
        }
        
        if let renewalDate = viewModel.renewalDate {
          HStack {
            Text("Next Billing Date")
              .font(.subheadline)
              .foregroundColor(.gray)
            
            Spacer()
            
            Text(renewalDate, style: .date)
              .font(.subheadline)
              .foregroundColor(.white)
          }
        }
        
        if !isOnboarding {
          HStack {
            Text("Status")
              .font(.subheadline)
              .foregroundColor(.gray)
            
            Spacer()
            
            Text("Active")
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundColor(.green)
          }
        }
      } else {
        // No active subscription
        HStack {
          Text("Current Plan")
            .font(.headline)
            .foregroundColor(.gray)
          
          Spacer()
          
          Text(viewModel.currentPlanName)
            .font(.title2)
            .fontWeight(.bold)
            .foregroundColor(.white)
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(16)
    .padding(.horizontal, 20)
  }
  
  // MARK: - Plan Options Section
  private var planOptionsSection: some View {
    VStack(spacing: 12) {
      Text("Available Plans")
        .font(.headline)
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
      
      ForEach(SubscriptionPlan.allCases, id: \.self) { plan in
        PlanOptionCard(
          plan: plan,
          isSelected: plan == viewModel.selectedPlan,
          billingCycle: viewModel.billingCycle
        ) {
          viewModel.selectedPlan = plan
        }
      }
    }
    .padding(.horizontal, 20)
  }
  
  // MARK: - Billing Cycle Section
  private var billingCycleSection: some View {
    VStack(spacing: 12) {
      Text("Billing Cycle")
        .font(.headline)
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
      
      HStack(spacing: 0) {
        monthlyButton
        yearlyButton
      }
      .background(Color.gray.opacity(0.1))
      .cornerRadius(12)
    }
    .padding(.horizontal, 20)
  }
  
  // MARK: - Monthly Button
  private var monthlyButton: some View {
    Button(action: {
      withAnimation(.easeInOut(duration: 0.2)) {
        viewModel.billingCycle = .monthly
      }
    }) {
      Text("Monthly")
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(viewModel.billingCycle == .monthly ? .white : .gray)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
          viewModel.billingCycle == .monthly ?
          AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing)) :
            AnyShapeStyle(Color.gray.opacity(0.1))
        )
    }
  }
  
  // MARK: - Yearly Button
  private var yearlyButton: some View {
    Button(action: {
      withAnimation(.easeInOut(duration: 0.2)) {
        viewModel.billingCycle = .yearly
      }
    }) {
      Text("Yearly (Save 20%)")
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(viewModel.billingCycle == .yearly ? .white : .gray)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
          viewModel.billingCycle == .yearly ?
          AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing)) :
            AnyShapeStyle(Color.gray.opacity(0.1))
        )
    }
  }
  
  // MARK: - Action Buttons Section
  private var actionButtonsSection: some View {
    VStack(spacing: 12) {
      // Subscribe button if no active subscription, otherwise show change plan
      if viewModel.hasActiveSubscription {
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
    .disabled(viewModel.isLoadingPurchase || viewModel.isServiceLoading)
  }
  
  // MARK: - Subscribe Button
  private var subscribeButton: some View {
    Button {
      Task {
        let result = await viewModel.handlePurchase()
        switch result {
        case .success, .pending, .productsNotReady, .failure:
          showingPurchaseAlert = true
        case .cancelled:
          break
        }
      }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "star.fill")
          .font(.headline)
          .foregroundColor(.white)
        
        Text("Subscribe to \(viewModel.selectedPlan.displayName)")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
      .cornerRadius(12)
    }
    .disabled(viewModel.isLoadingPurchase || viewModel.isServiceLoading)
  }
  
  // MARK: - Restore Purchases Button
  private var restorePurchasesButton: some View {
    Button {
      Task {
        let result = await viewModel.handleRestorePurchases()
        switch result {
        case .restored, .noneFound, .failure:
          showingRestoreAlert = true
        }
      }
    } label: {
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
      .background(LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
      .cornerRadius(12)
    }
    .disabled(viewModel.isLoadingPurchase || viewModel.isServiceLoading)
  }
  
  // MARK: - Change Plan Button
  private var changePlanButton: some View {
    Button {
      showingChangePlan = true
    } label: {
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
    .disabled(viewModel.isLoadingPurchase || viewModel.isServiceLoading)
  }
  
  // MARK: - Update Payment Button
  private var updatePaymentButton: some View {
    Button(action: {
      showingPaymentMethod = true
    }) {
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
      .background(LinearGradient(colors: [Color.teal.opacity(0.8), Color.cyan], startPoint: .leading, endPoint: .trailing))
      .cornerRadius(12)
    }
  }
  
  // MARK: - Cancel Subscription Button
  private var cancelSubscriptionButton: some View {
    Button(action: {
      showingCancelConfirmation = true
    }) {
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
      .background(LinearGradient(colors: [Color.white.opacity(0.9), Color.gray.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
      .cornerRadius(12)
    }
  }
}

#Preview("Subscription – Active Pro") {
  let service = SubscriptionService.previewActivePro
  let viewModel = SubscriptionViewModel(subscriptionService: service)
  return SubscriptionView(viewModel: viewModel)
}

#Preview("Subscription – No Plan") {
  let service = SubscriptionService.previewNone
  let viewModel = SubscriptionViewModel(subscriptionService: service)
  return SubscriptionView(viewModel: viewModel)
}
