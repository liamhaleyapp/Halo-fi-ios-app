//
//  CloseOnboardingButton.swift
//  Halo-fi-IOS
//
//  A reusable close button for dismissing onboarding with optional confirmation.
//

import SwiftUI

/// Close button shown during onboarding to allow users to exit early.
/// Shows a confirmation alert before dismissing to prevent accidental exits.
struct CloseOnboardingButton: View {
  let onClose: () -> Void
  
  /// Whether to show a confirmation alert before closing.
  /// Default is true for safety during onboarding.
  var requiresConfirmation: Bool = true
  
  @State private var showingConfirmation = false
  
  var body: some View {
    Button(action: handleTap) {
      Image(systemName: "xmark")
        .font(.title)
        .foregroundColor(.white)
        .padding(12)
        .background(
          Circle()
            .fill(Color.white.opacity(0.15))
        )
    }
    .frame(minWidth: 44, minHeight: 44, alignment: .center)
    .contentShape(Rectangle())
    .accessibilityLabel("Exit setup")
    .accessibilityHint("Leave onboarding. You can finish setting up your account later.")
    .confirmationDialog(
      "Exit Setup?",
      isPresented: $showingConfirmation,
      titleVisibility: .visible
    ) {
      Button("Exit", role: .destructive) {
        onClose()
      }
      Button("Continue Setup", role: .cancel) { }
    } message: {
      Text("You can finish setting up your account later from the app.")
    }
  }
  
  private func handleTap() {
    if requiresConfirmation {
      showingConfirmation = true
    } else {
      onClose()
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    
    VStack {
      HStack {
        Spacer()
        CloseOnboardingButton {
          print("Close tapped")
        }
        .padding()
      }
      Spacer()
    }
  }
}
