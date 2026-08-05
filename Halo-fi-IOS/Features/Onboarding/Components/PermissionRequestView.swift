//
//  PermissionRequestView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/16/25.
//
//  Microphone priming screen. Per App Store Guideline 5.1.1(iv) this is
//  purely informational: one neutral "Continue" button, no "Skip", no
//  reconsider alert, and no Settings redirect on denial. After the system
//  prompt the onboarding ALWAYS continues, whether the user granted or
//  denied — the app must not gate the flow on the permission here.
//

import SwiftUI

struct PermissionRequestView: View {
  // Scales with Dynamic Type (App Store Guideline 4).
  @ScaledMetric(relativeTo: .largeTitle) private var micIconSize: CGFloat = 60
  private let permissionManager = PermissionManager.shared
  @State private var isRequestingPermission = false

  /// Called once the system microphone prompt has been shown — regardless
  /// of grant or deny. Onboarding proceeds either way.
  let onContinue: () -> Void

  init(onContinue: @escaping () -> Void) {
    self.onContinue = onContinue
  }

  var body: some View {
    VStack(spacing: 30) {
      // Header — informational priming only.
      VStack(spacing: 16) {
        Image(systemName: "mic.fill")
          .font(.system(size: micIconSize))
          .foregroundColor(.blue)
          .accessibilityHidden(true)

        Text("Talk to Halo")
          .font(.title)
          .fontWeight(.bold)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)

        Text("Halo uses your microphone so you can manage your money by voice. It's how the app works for people who are blind or have low vision.")
          .font(.body)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }

      // Benefits list
      VStack(alignment: .leading, spacing: 12) {
        PermissionBenefitRow(
          icon: "waveform",
          title: "Voice Commands",
          description: "Control the app with your voice"
        )

        PermissionBenefitRow(
          icon: "speaker.wave.2",
          title: "Audio Feedback",
          description: "Get spoken responses and confirmations"
        )

        PermissionBenefitRow(
          icon: "accessibility",
          title: "Accessibility First",
          description: "Designed for users with vision impairments"
        )
      }
      .padding(.horizontal)

      Spacer()

      // Single neutral action — no skip, no reconsider.
      Button(action: requestPermission) {
        HStack {
          if isRequestingPermission {
            ProgressView()
              .scaleEffect(0.8)
              .accessibilityHidden(true)
          }
          Text("Continue")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(12)
      }
      .disabled(isRequestingPermission)
      .accessibilityLabel("Continue")
      .accessibilityHint(
        isRequestingPermission
        ? "Request in progress"
        : "Double tap to continue. You'll be asked to allow microphone access."
      )
      .padding(.horizontal)
    }
    .padding()
  }

  private func requestPermission() {
    isRequestingPermission = true

    Task {
      // Show the system prompt (a no-op if already decided). Onboarding
      // continues no matter the outcome — Apple 5.1.1(iv) bars gating the
      // flow on the grant or redirecting to Settings on denial. In-feature
      // "mic needed" affordances handle a later denial where it's allowed.
      _ = await permissionManager.requestMicrophonePermission()

      await MainActor.run {
        isRequestingPermission = false
        onContinue()
      }
    }
  }
}

#Preview {
  PermissionRequestView(onContinue: { print("Continue") })
}
