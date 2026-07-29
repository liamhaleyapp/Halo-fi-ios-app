//
//  AIConsentView.swift
//  Halo-fi-IOS
//
//  Required by Apple Guideline 5.1.1(i): obtain user permission before
//  sharing personal data with third-party AI services. Presented in the
//  onboarding flow after sign-up, before any agent conversation.
//
//  Decline path is a hard gate — voice agent is the entire product.
//  We sign the user out and return them to the sign-in screen rather
//  than maintain a degraded mode that wouldn't be usable for a voice-
//  first product.
//

import SwiftUI

struct AIConsentView: View {
  @Environment(UserManager.self) private var userManager

  let onAccept: () -> Void
  let onDecline: () -> Void

  @State private var policyVersion: String = "2026-05-04"
  @State private var showingDetails = false
  @State private var isProcessing = false
  @State private var showingDeclineConfirm = false
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        Image("HaloFiLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 80, height: 80)
          .padding(.top, 40)
          .accessibilityHidden(true)

        Text("Voice AI Consent")
          .font(.largeTitle)
          .fontWeight(.bold)
          .foregroundColor(.haloTextPrimary)
          .multilineTextAlignment(.center)

        VStack(alignment: .leading, spacing: 16) {
          Text("Halo Fi uses AI to power voice conversations.")
            .foregroundColor(.haloTextPrimary)

          Text("To answer your questions, we send transcripts and your account context to OpenAI, Anthropic, and ElevenLabs. None of them train models on your data.")
            .foregroundColor(.haloTextSecondary)

          Text("Halo Fi stores recordings on our own servers to improve quality. Withdraw consent anytime via Settings → Contact Us.")
            .foregroundColor(.haloTextSecondary)

          if showingDetails {
            VStack(alignment: .leading, spacing: 12) {
              Divider().background(Color.haloSeparator)

              Text("Data sent to providers:")
                .font(.headline)
                .foregroundColor(.haloTextPrimary)

              detailBullet("OpenAI / Anthropic", "Transcribed conversation text + account context (transactions, balances, budget, SSI status). No name, email, phone, or full account numbers.")
              detailBullet("ElevenLabs", "Raw voice recordings for speech-to-text, generated text for text-to-speech.")

              Text("Data stored by Halo Fi:")
                .font(.headline)
                .foregroundColor(.haloTextPrimary)
                .padding(.top, 8)

              detailBullet("Voice recordings + transcripts", "Encrypted at rest. Used to diagnose issues, audit agent quality, support fraud investigations, and train our own models on de-identified data.")
            }
            .padding(.top, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
          }

          Button {
            withAnimation(.easeInOut(duration: 0.2)) { showingDetails.toggle() }
          } label: {
            Text(showingDetails ? "Hide details" : "Tap for full details")
              .font(.subheadline)
              .foregroundColor(.blue)
              .underline()
          }
          .accessibilityLabel(showingDetails ? "Hide additional details" : "Show additional details about data sharing")

          Link(destination: URL(string: "https://halofiapp.com/privacy")!) {
            Text("View full Privacy Policy")
              .font(.subheadline)
              .foregroundColor(.blue)
              .underline()
          }
          .accessibilityHint("Opens the Halo Fi Privacy Policy in your browser")
        }
        .padding(.horizontal, 24)

        if let errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }

        Spacer(minLength: 24)

        VStack(spacing: 12) {
          Button(action: accept) {
            HStack {
              if isProcessing {
                ProgressView().progressViewStyle(.circular).tint(.white)
              }
              Text("Accept and Continue")
                .font(.headline)
                .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
              LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(16)
          }
          .disabled(isProcessing)
          .accessibilityHint("Grants consent and continues to the next step")

          Button(action: { showingDeclineConfirm = true }) {
            Text("I don't accept")
              .font(.subheadline)
              .foregroundColor(.haloTextSecondary)
          }
          .disabled(isProcessing)
          .accessibilityHint("Cancels sign-up and returns to the sign-in screen")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
      }
    }
    .background(Color.haloBackground.ignoresSafeArea())
    .alert("Without consent, Halo Fi can't function", isPresented: $showingDeclineConfirm) {
      Button("Go back", role: .cancel) { }
      Button("Sign out", role: .destructive) { decline() }
    } message: {
      Text("Halo Fi is a voice-first app and requires AI processing to work. You can sign back in any time after agreeing.")
    }
    .task {
      await fetchCurrentPolicyVersion()
    }
  }

  // MARK: - Actions

  private func accept() {
    isProcessing = true
    errorMessage = nil
    Task {
      defer { isProcessing = false }
      do {
        try await userManager.recordAIConsent(granted: true, policyVersion: policyVersion)
        onAccept()
      } catch {
        errorMessage = "Couldn't save your consent. Please check your connection and try again."
      }
    }
  }

  private func decline() {
    userManager.signOut()
    onDecline()
  }

  private func fetchCurrentPolicyVersion() async {
    struct LegalResp: Decodable { let last_updated: String }
    guard let url = URL(string: APIEndpoints.baseURL + APIEndpoints.Legal.privacy) else { return }
    do {
      let (data, _) = try await URLSession.shared.data(from: url)
      let resp = try JSONDecoder().decode(LegalResp.self, from: data)
      policyVersion = resp.last_updated
    } catch {
      // Fall back to hardcoded default — better to record a stale
      // version than block the user from accepting at all.
    }
  }

  // MARK: - Components

  @ViewBuilder
  private func detailBullet(_ heading: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(heading)
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundColor(.haloTextPrimary)
      Text(body)
        .font(.caption)
        .foregroundColor(.haloTextSecondary)
    }
  }
}

#Preview {
  AIConsentView(
    onAccept: { print("accepted") },
    onDecline: { print("declined") }
  )
  .environment(UserManager())
}
