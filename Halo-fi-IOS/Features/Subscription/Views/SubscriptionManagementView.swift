//
//  SubscriptionManagementView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 3/31/26.
//

import SwiftUI

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
            Text(subscriptionService.statusError == nil ? "Current Plan" : "Last Known Plan")
              .font(.subheadline)
              .foregroundColor(.haloTextSecondary)
            Text(subscriptionService.customerInfo == nil
                 ? (subscriptionService.statusError == nil ? "Checking your subscription..." : "Could not check subscription")
                 : subscriptionService.currentSubscription.displayName)
              .font(.headline)
              .foregroundColor(.haloTextPrimary)
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
                  .foregroundColor(.haloTextSecondary)
              } else {
                Text("\(subscriptionService.willRenew ? "Renews" : "Access until") \(renewalText)")
                  .font(.caption)
                  .foregroundColor(.haloTextSecondary)
              }
            }
          } else {
            Text(subscriptionService.customerInfo == nil ? "" : "Inactive")
              .font(.caption)
              .foregroundColor(.red)
          }
        }
        .padding(16)
        .background(Color.haloSecondaryBackground)
        .cornerRadius(16)
        .accessibilityElement(children: .combine)

        if let message = subscriptionService.statusError {
          Text(message)
            .foregroundColor(.haloTextPrimary)
          Button("Retry subscription check") {
            Task { await subscriptionService.checkSubscriptionStatus() }
          }
          .frame(minHeight: 44)
        }

        // Only offer a new purchase after a successful account-specific check.
        // A missing/unavailable result must not look like a cancelled subscription.
        if subscriptionService.customerInfo != nil && subscriptionService.statusError == nil {
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
        }

        // Cancel — de-emphasized text link
        if subscriptionService.hasActiveSubscription {
          Button {
            openSubscriptionManagement()
          } label: {
            Text("Manage App Store Subscription")
              .font(.subheadline)
              .foregroundColor(.haloTextSecondary)
          }
          .frame(minHeight: 44)
          .padding(.top, 16)
          .accessibilityHint("Opens Apple subscription management")
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 100)
    }
    .background(Color.haloBackground.ignoresSafeArea())
    .navigationTitle("Subscription")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showingPaywall) {
      AccountSubscriptionPaywall {
        showingPaywall = false
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


/// Both subscription entry points use the same account-owned checkout.
struct AccountSubscriptionPaywall: View {
  @Environment(SubscriptionService.self) private var subscriptionService
  var displayCloseButton = true
  var onComplete: () -> Void

  var body: some View {
    SubscriptionCheckoutView(service: subscriptionService,
                             displayCloseButton: displayCloseButton, onComplete: onComplete)
  }
}

struct SubscriptionCheckoutView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var checkout: SubscriptionCheckout
  private let service: SubscriptionService
  var displayCloseButton = true
  var onComplete: () -> Void
  @State private var completionDelivered = false
  @AccessibilityFocusState private var focus: Focus?
  private enum Focus: Hashable { case heading, status }
  private var billingCycleLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
  }

  init(service: SubscriptionService, displayCloseButton: Bool = true, onComplete: @escaping () -> Void) {
    self.service = service
    self._checkout = State(initialValue: SubscriptionCheckout(service: service))
    self.displayCloseButton = displayCloseButton
    self.onComplete = onComplete
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Choose your plan")
          .font(.title.bold())
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("checkoutHeading")
          .accessibilityFocused($focus, equals: .heading)

        Text("Choose your billing cycle and plan.")

        if !checkout.loaded {
          ProgressView("Loading subscription plans...")
        }

        if let error = checkout.catalogError {
          Text(error)
            .accessibilityIdentifier("checkoutCatalogError")
          Button { Task { await checkout.load() } } label: {
            SubscriptionActionLabel("Retry loading plans")
          }
            .buttonStyle(.bordered)
            .disabled(checkout.isBusy)
        }

        if !checkout.plans.isEmpty {
          billingCycleLayout {
            ForEach(SubscriptionBillingCycle.allCases) { cycle in
              Button {
                checkout.selectCycle(cycle)
              } label: {
                Text(cycle.title)
                  .font(.body.weight(.semibold))
                  .fixedSize(horizontal: false, vertical: true)
                  .frame(maxWidth: .infinity, minHeight: 48)
                  .foregroundStyle(checkout.billingCycle == cycle ? Color(uiColor: .systemBackground) : Color.primary)
                  .background(checkout.billingCycle == cycle ? Color(uiColor: .label) : Color.clear)
                  .clipShape(RoundedRectangle(cornerRadius: 10))
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("checkoutCycle_\(cycle.rawValue)")
              .accessibilityAddTraits(checkout.billingCycle == cycle ? [.isSelected] : [])
              .accessibilityHint("Shows \(cycle.title.lowercased()) prices for Basic, Pro, and Max.")
              .disabled(checkout.isBusy || checkout.awaitingConfirmation)
            }
          }
          .padding(4)
          .background(Color(uiColor: .secondarySystemBackground))
          .clipShape(RoundedRectangle(cornerRadius: 14))
          .accessibilityElement(children: .contain)
          .accessibilityLabel("Billing cycle")

          if checkout.visiblePlans.isEmpty {
            Text("No \(checkout.billingCycle.title.lowercased()) plans are available right now. Choose another billing option or try again later.")
          }
        }

        ForEach(checkout.visiblePlans) { plan in
          Button {
            checkout.selectedID = plan.id
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text(plan.displayTitle).font(.title2.bold())
              Text("\(plan.price) \(plan.billingLabel)")
                .font(.title3.weight(.semibold))
              if plan.hasIntroductoryOffer { Text(plan.terms).font(.body) }
              if !plan.detail.isEmpty { Text(plan.detail).font(.body) }
              if checkout.selectedID == plan.id {
                Text("Selected").font(.body.weight(.semibold))
              }
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
              RoundedRectangle(cornerRadius: 12)
                .stroke(checkout.selectedID == plan.id ? Color.haloTextPrimary : Color.haloTextSecondary,
                        lineWidth: checkout.selectedID == plan.id ? 3 : 1)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("checkoutPlan_\(plan.id)")
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(checkout.selectedID == plan.id ? [.isSelected] : [])
          .accessibilityHint("Selects this plan. Apple will ask you to confirm before purchasing.")
          .disabled(checkout.isBusy || checkout.awaitingConfirmation)
        }

        if !checkout.plans.isEmpty {
          Text("Subscriptions renew automatically unless cancelled in App Store subscription settings. Apple shows the final price and any change to an existing plan before you confirm.")

          Button {
            Task { await checkout.purchase() }
          } label: {
            Text(checkout.selectedPlan.map { "Continue with \($0.displayTitle) \(checkout.billingCycle.title)" } ?? "Select a plan above")
              .font(.headline)
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity, minHeight: 44)
              .padding(.vertical, 8)
          }
          .buttonStyle(.borderedProminent)
          .tint(Color(uiColor: .label))
          .foregroundStyle(Color(uiColor: .systemBackground))
          .accessibilityIdentifier("checkoutPurchase")
          .disabled(!checkout.canPurchase)
        }

        if checkout.isBusy, checkout.loaded {
          ProgressView("Checking with the App Store...")
        }

        if let message = checkout.message {
          Text(message)
            .accessibilityIdentifier("checkoutStatus")
            .accessibilityFocused($focus, equals: .status)
        }

        if checkout.awaitingConfirmation {
          Button { Task { await checkout.checkStatus() } } label: {
            SubscriptionActionLabel("Check subscription again")
          }
            .buttonStyle(.bordered)
            .disabled(checkout.isBusy)
        }

        Button { Task { await checkout.restore() } } label: {
          SubscriptionActionLabel("Restore purchases")
        }
          .buttonStyle(.bordered)
          .disabled(checkout.isBusy)
          .accessibilityIdentifier("checkoutRestore")

        SubscriptionLegalLinks()

        Button { close() } label: {
          SubscriptionActionLabel(displayCloseButton ? "Close" : "Back")
        }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("checkoutClose")
      }
      .padding(20)
    }
    .foregroundStyle(Color.primary)
    .background(Color(uiColor: .systemBackground))
    .task {
      await checkout.load()
      guard checkout.isCurrent else { return }
      focus = .heading
    }
    .task(id: checkout.message) {
      guard checkout.message != nil, checkout.isCurrent else { return }
      await Task.yield()
      focus = .status
    }
    .onChange(of: service.sessionRevision) { _, _ in close() }
    .onChange(of: checkout.completed) { _, completed in
      guard completed, checkout.isCurrent, !completionDelivered else { return }
      completionDelivered = true
      onComplete()
    }
    .onDisappear { checkout.close() }
    .accessibilityAction(.escape) { close() }
  }

  private func close() {
    checkout.close()
    dismiss()
  }
}


/// Size the label inside the control so its actual accessibility/hit frame,
/// rather than only the surrounding layout, meets the minimum target size.
struct SubscriptionActionLabel: View {
  let title: String
  init(_ title: String) { self.title = title }
  var body: some View {
    Text(title)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Rectangle())
  }
}
