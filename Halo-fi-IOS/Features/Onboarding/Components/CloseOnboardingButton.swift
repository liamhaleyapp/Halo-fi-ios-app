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
        .foregroundColor(.haloTextPrimary)
        .padding(12)
        .background(
          // Adaptive translucent chip so both the glyph and the disc stay
          // visible in Light (was a white glyph on a white-15% disc that
          // washed out on a light background).
          Circle()
            .fill(Color(.tertiarySystemFill))
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
    Color.haloBackground.ignoresSafeArea()

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
