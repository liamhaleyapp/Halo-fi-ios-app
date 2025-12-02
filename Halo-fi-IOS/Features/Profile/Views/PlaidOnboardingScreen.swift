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
  
  init(
    onComplete: (() -> Void)? = nil,
    onBack: (() -> Void)? = nil
  ) {
    self.onComplete = onComplete
    self.onBack = onBack
  }
  
  var body: some View {
    NavigationStack {
      PlaidOnboardingView(
        onComplete: onComplete,
        onBack: onBack
      )
      .navigationTitle("Connect Bank")
      .navigationBarTitleDisplayMode(.large)
    }
  }
}
