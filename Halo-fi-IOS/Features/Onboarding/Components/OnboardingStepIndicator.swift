//
//  OnboardingStepIndicator.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/10/25.
//

import SwiftUI

struct OnboardingStepIndicator: View {
  let currentStep: OnboardingStep
  let signUpCompleted: Bool
  let subscriptionCompleted: Bool
  
  var body: some View {
    HStack(spacing: 12) {
      ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
        StepIndicatorDot(
          step: step,
          isActive: step.rawValue == currentStep.rawValue,
          isCompleted: isStepCompleted(step)
        )
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
  }
  
  private func isStepCompleted(_ step: OnboardingStep) -> Bool {
    switch step {
    case .signUp:
      return signUpCompleted
    case .subscription:
      return subscriptionCompleted
    case .plaid:
      return false // Plaid is the final step
    }
  }
}

struct StepIndicatorDot: View {
  let step: OnboardingStep
  let isActive: Bool
  let isCompleted: Bool
  
  var body: some View {
    VStack(spacing: 4) {
      ZStack {
        Circle()
          .fill(isCompleted || isActive ? Color.blue : Color.gray.opacity(0.3))
          .frame(width: 12, height: 12)
        
        if isCompleted {
          Image(systemName: "checkmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
        }
      }
      
      Text(step.title)
        .font(.caption2)
        .foregroundColor(isActive ? .white : .gray)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VStack {
      OnboardingStepIndicator(
        currentStep: .subscription,
        signUpCompleted: true,
        subscriptionCompleted: false
      )
    }
  }
}
