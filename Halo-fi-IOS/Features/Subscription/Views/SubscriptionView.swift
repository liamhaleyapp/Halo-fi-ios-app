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
  
  var body: some View {
    NavigationStack {
      ZStack {
        // Content
        ScrollView {
          VStack(spacing: 16) {
            currentPlanSection
            planOptionsSection
            billingCycleSection
            SubscriptionActionButtonsSection(
              hasActiveSubscription: viewModel.hasActiveSubscription,
              isOnboarding: isOnboarding,
              isBusy: viewModel.isBusy,
              selectedPlanName: viewModel.selectedPlan.displayName,
              onContinue: onContinue,
              onSubscribe: {
                Task {
                  _ = await viewModel.handlePurchase()
                }
              },
              onChangePlan: {
                showingChangePlan = true
              },
              onRestore: {
                Task {
                  _ = await viewModel.handleRestorePurchases()
                }
              },
              onUpdatePayment: {
                showingPaymentMethod = true
              },
              onCancelSubscription: {
                showingCancelConfirmation = true
              }
            )
          }
        }
        
        // Loading overlay
        if viewModel.isBusy {
          Color(.systemBackground).opacity(0.7)
            .ignoresSafeArea()
          
          VStack(spacing: 16) {
            ProgressView()
              .scaleEffect(1.5)
            Text("Processing...")
              .foregroundColor(.primary)
              .font(.subheadline)
          }
        }
      }
      .navigationTitle(isOnboarding ? "" : "Subscription")
      .navigationBarTitleDisplayMode(isOnboarding ? .automatic : .large)
      .toolbar {
        if !isOnboarding {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              dismiss()
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Settings")
              }
            }
            .accessibilityLabel("Back to Settings")
          }
        }
      }
      .navigationBarHidden(isOnboarding)
    }
    .task {
      await viewModel.onAppear()
    }
    .alert(item: $viewModel.activeEvent) { event in
      switch event {
      case .purchase(let message):
        return Alert(
          title: Text("Purchase"),
          message: Text(message),
          dismissButton: .default(Text("OK"))
        )
      case .restore(let message):
        return Alert(
          title: Text("Restore Purchases"),
          message: Text(message),
          dismissButton: .default(Text("OK"))
        )
      case .info(let message):
        return Alert(
          title: Text("Info"),
          message: Text(message),
          dismissButton: .default(Text("OK"))
        )
      }
    }
    .alert("Change Plan", isPresented: $showingChangePlan) {
      Button("Cancel", role: .cancel) { }
      Button("Change", role: .destructive) {
        Task {
          _ = await viewModel.handlePurchase()
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
}
  // MARK: - Action Buttons Section
  

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
