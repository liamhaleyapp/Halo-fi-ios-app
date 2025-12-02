//
//  PlaidOnboardingStep.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/1/25.
//

import SwiftUI

struct PlaidOnboardingStep: View {
  let coordinator: OnboardingCoordinator
  @Environment(BankDataManager.self) private var bankDataManager
  @Environment(UserManager.self) private var userManager
  let onComplete: () -> Void
  let onBack: () -> Void
  
  @State private var hasCheckedAccounts = false
  
  var body: some View {
    PlaidOnboardingView(onComplete: onComplete, onBack: onBack)
  }
}
