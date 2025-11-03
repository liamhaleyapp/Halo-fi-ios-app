//
//  SubscriptionView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SubscriptionView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(SubscriptionService.self) private var subscriptionService
  
  // MARK: - Subscription State
  @State private var selectedPlan: SubscriptionPlan = .pro
  @State private var billingCycle: BillingCycle = .monthly
  @State private var showingChangePlan = false
  @State private var showingPaymentMethod = false
  @State private var showingCancelConfirmation = false
  @State private var showingPurchaseAlert = false
  @State private var purchaseAlertMessage = ""
  @State private var showingRestoreAlert = false
  @State private var restoreAlertMessage = ""
  @State private var isLoadingPurchase = false
  
  var body: some View {
    NavigationView {
      ZStack {
        // Background
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 16) {
          headerView
          currentPlanSection
          planOptionsSection
          billingCycleSection
          actionButtonsSection
        }
        
        // Loading overlay
        if isLoadingPurchase || subscriptionService.isLoading {
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
    }
    .navigationBarHidden(true)
    .onAppear {
      // If products haven't loaded, retry initialization
      if subscriptionService.availablePackages.isEmpty && !subscriptionService.isLoading {
        Task {
          await subscriptionService.initialize()
        }
      }
      
      // Update selected plan from subscription when view appears
      updateSelectedPlanFromSubscription()
    }
    .alert("Purchase", isPresented: $showingPurchaseAlert) {
      Button("OK", role: .cancel) { }
    } message: {
      Text(purchaseAlertMessage)
    }
    .alert("Restore Purchases", isPresented: $showingRestoreAlert) {
      Button("OK", role: .cancel) { }
    } message: {
      Text(restoreAlertMessage)
    }
    .alert("Change Plan", isPresented: $showingChangePlan) {
      Button("Cancel", role: .cancel) { }
      Button("Change", role: .destructive) {
        Task {
          await handlePurchase()
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
        Task {
          await handleCancelSubscription()
        }
      }
    } message: {
      Text("Are you sure you want to cancel your subscription? You'll lose access to premium features at the end of your current billing period. You can also manage this in Settings > Apple ID > Subscriptions.")
    }
  }
  
  // MARK: - Helper Methods
  
  private func updateSelectedPlanFromSubscription() {
    switch subscriptionService.currentSubscription {
    case .basic:
      selectedPlan = .basic
    case .pro:
      selectedPlan = .pro
    case .max:
      selectedPlan = .max
    default:
      break
    }
  }
  
  private func handlePurchase() async {
    // Check if products are loaded
    if subscriptionService.availablePackages.isEmpty {
      // Try to initialize if not already loading
      if !subscriptionService.isLoading {
        await subscriptionService.initialize()
      }
      
      // Wait a bit for products to load if still loading
      if subscriptionService.isLoading {
        var waitCount = 0
        while subscriptionService.isLoading && waitCount < 10 {
          try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
          waitCount += 1
        }
      }
      
      // Check again
      if subscriptionService.availablePackages.isEmpty {
        await MainActor.run {
          purchaseAlertMessage = "Products are still loading. Please wait a moment and try again."
          showingPurchaseAlert = true
        }
        return
      }
    }
    
    isLoadingPurchase = true
    
    let productId = selectedPlan.productId(for: billingCycle)
    
    do {
      let result = try await subscriptionService.purchase(productId: productId)
      
      await MainActor.run {
        isLoadingPurchase = false
        
        if result.success {
          purchaseAlertMessage = "Successfully subscribed to \(selectedPlan.displayName)!"
          updateSelectedPlanFromSubscription()
        } else {
          purchaseAlertMessage = "Purchase completed but subscription status is pending."
        }
        showingPurchaseAlert = true
      }
    } catch SubscriptionError.purchaseCancelled {
      await MainActor.run {
        isLoadingPurchase = false
      }
      // User cancelled - don't show error
    } catch {
      await MainActor.run {
        isLoadingPurchase = false
        purchaseAlertMessage = error.localizedDescription
        showingPurchaseAlert = true
      }
    }
  }
  
  private func handleRestorePurchases() async {
    isLoadingPurchase = true
    
    do {
      try await subscriptionService.restorePurchases()
      
      await MainActor.run {
        isLoadingPurchase = false
        updateSelectedPlanFromSubscription()
        
        if subscriptionService.hasActiveSubscription {
          restoreAlertMessage = "Purchases restored successfully! You have access to \(subscriptionService.currentSubscription.displayName)."
        } else {
          restoreAlertMessage = "No active purchases found to restore."
        }
        showingRestoreAlert = true
      }
    } catch {
      await MainActor.run {
        isLoadingPurchase = false
        restoreAlertMessage = error.localizedDescription
        showingRestoreAlert = true
      }
    }
  }
  
  private func handleCancelSubscription() {
    // iOS doesn't allow programmatic cancellation - direct users to Settings
    showingPaymentMethod = false
    
    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
      UIApplication.shared.open(url)
    }
  }
  
  // MARK: - Header View
  private var headerView: some View {
    HStack {
      Button(action: {
        dismiss()
      }) {
        Image(systemName: "chevron.left")
          .font(.title2)
          .foregroundColor(.white)
          .frame(width: 40, height: 40)
          .background(Color.gray.opacity(0.2))
          .clipShape(Circle())
      }
      
      Spacer()
      
      Text("Subscription")
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(.white)
      
      Spacer()
      
      // Placeholder for balance
      Color.clear
        .frame(width: 40, height: 40)
    }
    .padding(.horizontal, 20)
    .padding(.top, 15)
    .padding(.bottom, 20)
  }
  
  // MARK: - Current Plan Section
  private var currentPlanSection: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Current Plan")
          .font(.headline)
          .foregroundColor(.gray)
        
        Spacer()
        
        Text(subscriptionService.currentSubscription.displayName)
          .font(.title2)
          .fontWeight(.bold)
          .foregroundColor(.white)
      }
      
      if let renewalDate = subscriptionService.renewalDate {
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
      
      if subscriptionService.hasActiveSubscription {
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
          isSelected: plan == selectedPlan,
          billingCycle: billingCycle
        ) {
          selectedPlan = plan
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
        billingCycle = .monthly
      }
    }) {
      Text("Monthly")
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(billingCycle == .monthly ? .white : .gray)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
          billingCycle == .monthly ?
          AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing)) :
            AnyShapeStyle(Color.gray.opacity(0.1))
        )
    }
  }
  
  // MARK: - Yearly Button
  private var yearlyButton: some View {
    Button(action: {
      withAnimation(.easeInOut(duration: 0.2)) {
        billingCycle = .yearly
      }
    }) {
      Text("Yearly (Save 20%)")
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(billingCycle == .yearly ? .white : .gray)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
          billingCycle == .yearly ?
          AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing)) :
            AnyShapeStyle(Color.gray.opacity(0.1))
        )
    }
  }
  
  // MARK: - Action Buttons Section
  private var actionButtonsSection: some View {
    VStack(spacing: 12) {
      // Subscribe button if no active subscription, otherwise show change plan
      if subscriptionService.hasActiveSubscription {
        changePlanButton
        updatePaymentButton
        cancelSubscriptionButton
      } else {
        subscribeButton
        restorePurchasesButton
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 40)
  }
  
  // MARK: - Subscribe Button
  private var subscribeButton: some View {
    Button(action: {
      Task {
        await handlePurchase()
      }
    }) {
      HStack(spacing: 12) {
        Image(systemName: "star.fill")
          .font(.headline)
          .foregroundColor(.white)
        
        Text("Subscribe to \(selectedPlan.displayName)")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
      .cornerRadius(12)
    }
    .disabled(isLoadingPurchase || subscriptionService.isLoading)
  }
  
  // MARK: - Restore Purchases Button
  private var restorePurchasesButton: some View {
    Button(action: {
      Task {
        await handleRestorePurchases()
      }
    }) {
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
    .disabled(isLoadingPurchase || subscriptionService.isLoading)
  }
  
  // MARK: - Change Plan Button
  private var changePlanButton: some View {
    Button(action: {
      Task {
        await handlePurchase()
      }
    }) {
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
      .background(LinearGradient(colors: [Color.teal, Color.blue], startPoint: .leading, endPoint: .trailing))
      .cornerRadius(12)
    }
    .disabled(isLoadingPurchase || subscriptionService.isLoading)
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

// MARK: - Plan Option Card

struct PlanOptionCard: View {
  let plan: SubscriptionPlan
  let isSelected: Bool
  let billingCycle: BillingCycle
  let onSelect: () -> Void
  
  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 16) {
        // Plan Icon
        Image(systemName: plan.iconName)
          .font(.title2)
          .foregroundColor(isSelected ? .white : .purple)
          .frame(width: 40, height: 40)
          .background(
            isSelected ?
            AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)) :
              AnyShapeStyle(Color.purple.opacity(0.1))
          )
          .clipShape(Circle())
        
        // Plan Details
        VStack(alignment: .leading, spacing: 4) {
          Text(plan.displayName)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
          
          Text(plan.description)
            .font(.caption)
            .foregroundColor(.gray)
            .lineLimit(2)
          
          Text(billingCycle == .monthly ? plan.monthlyPrice : plan.yearlyPrice)
            .font(.title3)
            .fontWeight(.bold)
            .foregroundColor(.purple)
        }
        
        Spacer()
        
        // Selection Indicator
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.title2)
            .foregroundColor(.purple)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(isSelected ? Color.purple.opacity(0.1) : Color.gray.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
      )
    }
    .buttonStyle(PlainButtonStyle())
  }
}

// MARK: - Models

enum SubscriptionPlan: CaseIterable {
  case basic, pro, max
  
  var displayName: String {
    switch self {
    case .basic: return "Basic"
    case .pro: return "Pro"
    case .max: return "Max"
    }
  }
  
  var iconName: String {
    switch self {
    case .basic: return "star.fill"
    case .pro: return "star.circle.fill"
    case .max: return "crown.fill"
    }
  }
  
  var description: String {
    switch self {
    case .basic: return "20 mins voice convo / No instant refresh"
    case .pro: return "45 mins convo / 5 instant account refreshes"
    case .max: return "120 mins convo / 15 instant refreshes"
    }
  }
  
  var monthlyPrice: String {
    switch self {
    case .basic: return "$12.99/mo"
    case .pro: return "$24.99/mo"
    case .max: return "$49.99/mo"
    }
  }
  
  var yearlyPrice: String {
    switch self {
    case .basic: return "$144.99/yr"
    case .pro: return "$274.99/yr"
    case .max: return "$549.99/yr"
    }
  }
  
  // RevenueCat Product IDs
  var monthlyProductId: String {
    switch self {
    case .basic: return "com.halofi.basic.monthly"
    case .pro: return "com.halofi.pro.monthly"
    case .max: return "com.halofi.max.monthly"
    }
  }
  
  var yearlyProductId: String {
    switch self {
    case .basic: return "com.halofi.basic.yearly"
    case .pro: return "com.halofi.pro.yearly"
    case .max: return "com.halofi.max.yearly"
    }
  }
  
  func productId(for billingCycle: BillingCycle) -> String {
    switch billingCycle {
    case .monthly: return monthlyProductId
    case .yearly: return yearlyProductId
    }
  }
}

enum BillingCycle {
  case monthly, yearly
}

#Preview {
  SubscriptionView()
}
