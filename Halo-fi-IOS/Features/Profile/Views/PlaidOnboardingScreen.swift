//
//  PlaidOnboardingScreen.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/1/25.
//

import SwiftUI

struct PlaidOnboardingScreen: View {
  let onComplete: (() -> Void)?
  let onBack: (() -> Void)?
  var isOnboarding: Bool

  init(
    onComplete: (() -> Void)? = nil,
    onBack: (() -> Void)? = nil,
    isOnboarding: Bool = false
  ) {
    self.onComplete = onComplete
    self.onBack = onBack
    self.isOnboarding = isOnboarding
  }

  var body: some View {
    NavigationStack {
      PlaidOnboardingView(
        onComplete: onComplete,
        onBack: onBack,
        isOnboarding: isOnboarding
      )
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}
