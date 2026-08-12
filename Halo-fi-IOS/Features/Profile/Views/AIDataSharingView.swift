//
//  AIDataSharingView.swift
//  Halo-fi-IOS
//
//  Persistent in-app disclosure for Apple Guideline 5.1.1(i) / 5.1.2(i).
//  AIConsentView collects permission once at onboarding; App Review needs
//  the same disclosure reachable at any time (a pre-consented demo account
//  never sees the onboarding gate), plus a real control to withdraw —
//  the privacy policy on its own is explicitly not sufficient.
//
//  Withdrawing signs the user out. That mirrors AIConsentView's decline
//  path and guarantees the consent gate re-runs on next sign-in rather
//  than leaving a signed-in session in a half-consented state.
//

import SwiftUI

struct AIDataSharingView: View {
  @Environment(UserManager.self) private var userManager

  @State private var isWithdrawing = false
  @State private var showingWithdrawConfirm = false
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Halo Fi uses AI to answer your questions by voice. Here is exactly what leaves your device, and who receives it.")
          .foregroundColor(.haloTextPrimary)

        section(
          "OpenAI and Anthropic",
          "What we send: the text of what you say, plus the account context needed to answer — transactions, balances, budget figures, and SSI status. We do not send your name, email, phone number, or full account numbers.",
          "Why: these models generate Halo's answers.",
          "Neither provider trains models on your data."
        )

        section(
          "ElevenLabs",
          "What we send: your raw voice recording for speech-to-text, and Halo's reply text for text-to-speech.",
          "Why: this is what lets you talk to Halo instead of typing.",
          "ElevenLabs does not train models on your data."
        )

        section(
          "Halo Fi's own servers",
          "What we store: your voice recordings and transcripts, encrypted at rest.",
          "Why: to diagnose issues, audit answer quality, support fraud investigations, and train our own models on de-identified data.",
          nil
        )

        Link(destination: URL(string: "https://halofiapp.com/privacy")!) {
          Text("View full Privacy Policy")
            .font(.subheadline)
            .foregroundColor(.blue)
            .underline()
        }
        .accessibilityHint("Opens the Halo Fi Privacy Policy in your browser")

        Divider().background(Color.haloSeparator)

        VStack(alignment: .leading, spacing: 8) {
          Text("Withdraw consent")
            .font(.headline)
            .foregroundColor(.haloTextPrimary)
          Text("Halo Fi is a voice-first app and can't function without AI processing. Withdrawing consent signs you out. You can accept again any time you sign back in.")
            .font(.subheadline)
            .foregroundColor(.haloTextSecondary)
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundColor(.red)
        }

        Button(action: { showingWithdrawConfirm = true }) {
          HStack {
            if isWithdrawing {
              ProgressView().progressViewStyle(.circular)
            }
            Text("Withdraw consent and sign out")
              .font(.headline)
          }
          .foregroundColor(.red)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .background(Color.haloSecondaryBackground)
          .cornerRadius(12)
        }
        .disabled(isWithdrawing)
        .accessibilityHint("Revokes AI processing consent and signs you out of Halo Fi")
      }
      .padding(20)
      .readableContentWidth()
    }
    .background(Color.haloBackground.ignoresSafeArea())
    .navigationTitle("AI & Data Sharing")
    .navigationBarTitleDisplayMode(.inline)
    .alert("Withdraw consent?", isPresented: $showingWithdrawConfirm) {
      Button("Cancel", role: .cancel) { }
      Button("Withdraw and sign out", role: .destructive) { withdraw() }
    } message: {
      Text("You'll be signed out. Halo Fi can't answer questions without sending data to the AI providers listed here.")
    }
  }

  // MARK: - Actions

  private func withdraw() {
    isWithdrawing = true
    errorMessage = nil
    Task {
      defer { isWithdrawing = false }
      do {
        try await userManager.recordAIConsent(
          granted: false,
          policyVersion: userManager.aiConsentPolicyVersion ?? ""
        )
        userManager.signOut()
      } catch {
        errorMessage = "Couldn't record your withdrawal. Please check your connection and try again."
      }
    }
  }

  // MARK: - Components

  @ViewBuilder
  private func section(_ title: String, _ sent: String, _ why: String, _ note: String?) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.headline)
        .foregroundColor(.haloTextPrimary)
      Text(sent)
        .font(.subheadline)
        .foregroundColor(.haloTextSecondary)
      Text(why)
        .font(.subheadline)
        .foregroundColor(.haloTextSecondary)
      if let note {
        Text(note)
          .font(.subheadline)
          .foregroundColor(.haloTextSecondary)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.haloSecondaryBackground)
    .cornerRadius(12)
  }
}

#Preview {
  NavigationStack {
    AIDataSharingView()
      .environment(UserManager())
  }
}
