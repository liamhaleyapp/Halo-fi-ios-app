//
//  PlaidOnboardingView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
import LinkKit

struct PlaidOnboardingView: View {
  @SwiftUI.Environment(\.dismiss) private var dismiss
  @SwiftUI.Environment(UserManager.self) private var userManager
  @SwiftUI.Environment(BankDataManager.self) private var bankDataManager
  @SwiftUI.Environment(PlaidManager.self) private var plaidManager

  @State private var viewModel: PlaidOnboardingViewModel?

  var onComplete: (() -> Void)?
  var onBack: (() -> Void)?

  init(
    onComplete: (() -> Void)? = nil,
    onBack: (() -> Void)? = nil
  ) {
    self.onComplete = onComplete
    self.onBack = onBack
  }

  var body: some View {
    ZStack {
      if let viewModel = viewModel {
        // Plaid Link interface (when ready)
        if viewModel.showingPlaidLink, let handler = viewModel.linkHandler {
          LinkController(handler: handler)
            .background(Color(.systemBackground))
        }
        // Loading state
        else if viewModel.isLoading || bankDataManager.isSyncing {
          LoadingView()
        }
        // Initial state - show intro and start button
        else {
          PlaidIntroView {
            viewModel.startPlaidFlow(
              bankDataManager: bankDataManager,
              userManager: userManager
            )
          }
        }
      } else {
        // Show loading while viewModel initializes
        LoadingView()
      }
    }
    .toolbar {
      if let onBack = viewModel?.onBack {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            onBack()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "chevron.left")
              Text("Back")
            }
          }
          .accessibilityLabel("Go back to previous step")
        }
      }
    }
    .task {
      // Initialize viewModel with the environment's PlaidManager
      if viewModel == nil {
        viewModel = PlaidOnboardingViewModel(plaidManager: plaidManager)
      }

      guard let viewModel = viewModel else { return }

      // 1. Wire callbacks
      viewModel.onComplete = onComplete
      viewModel.onBack = onBack
      viewModel.onDismiss = { dismiss() }

      // 2. Check accounts and maybe start flow
      await viewModel.bootstrapIfNeeded(
        userManager: userManager,
        bankDataManager: bankDataManager
      )
    }
    .alert("Connection Error", isPresented: Binding(
      get: { viewModel?.showingError ?? false },
      set: { viewModel?.showingError = $0 }
    )) {
      Button("OK") {
        viewModel?.handleErrorDismissal(userManager: userManager)
      }
    } message: {
      Text(viewModel?.errorMessage ?? "")
    }
    .onChange(of: viewModel?.shouldSignOut) { _, newValue in
      if newValue == true {
        viewModel?.handleSignOut(userManager: userManager)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Connect Bank")
    .accessibilityHint("Step 3 of 3 in the setup process")
  }
}

#Preview {
  PlaidOnboardingView()
    .environment(UserManager())
    .environment(BankDataManager())
    .environment(PlaidManager())
}
