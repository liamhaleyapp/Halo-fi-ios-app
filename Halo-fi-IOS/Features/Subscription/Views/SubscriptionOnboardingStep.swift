import SwiftUI

struct SubscriptionOnboardingStep: View {
  let coordinator: OnboardingCoordinator
  @Environment(SubscriptionService.self) private var subscriptionService
  let onComplete: () -> Void
  let onBack: (() -> Void)?
  @State private var completed = false
  @State private var owner: UUID?

  var body: some View {
    SubscriptionOnboardingFlowView(
      onComplete: completeIfSubscribed,
      hideBackButton: onBack == nil
    )
    .task {
      owner = subscriptionService.sessionRevision
      let generation = SessionLifetime.shared.current
      await subscriptionService.initialize()
      guard SessionLifetime.shared.isCurrent(generation) else { return }
      completeIfSubscribed()
    }
    .onChange(of: subscriptionService.hasActiveSubscription) { _, active in
      if active { completeIfSubscribed() }
    }
  }

  private func completeIfSubscribed() {
    guard owner == subscriptionService.sessionRevision, !completed, subscriptionService.hasActiveSubscription else { return }
    completed = true
    coordinator.markStepCompleted(.subscription)
    onComplete()
  }
}
