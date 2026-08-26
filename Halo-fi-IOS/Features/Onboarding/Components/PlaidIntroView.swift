//
//  PlaidIntroView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/1/25.
//

import SwiftUI

struct PlaidIntroView: View {
  // Scales with Dynamic Type (App Store Guideline 4).
  @ScaledMetric(relativeTo: .largeTitle) private var headerIconSize: CGFloat = 64
  /// Institutions the user already has connected. Shown as an explicit
  /// "Already connected" list (with VoiceOver labels) so a blind user never
  /// has to infer linked state from Plaid Link's own UI — re-linking the
  /// same login silently creates duplicate accounts.
  var alreadyLinked: [String] = []
  /// True when the linked-accounts check failed: say the state is
  /// unconfirmed rather than implying nothing is connected.
  var linkedStateUnconfirmed = false
  let action: () -> Void

  @State private var showingRelinkConfirmation = false

  var body: some View {

    ScrollView {
      VStack(spacing: 24) {
        // Icon
        Image(systemName: "lock.shield.fill")
          .font(.system(size: headerIconSize))
          .foregroundStyle(.blue)
          .padding(.top, 40)

        // Title
        Text("Connect Your Bank Account")
          .font(.largeTitle)
          .fontWeight(.bold)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)

        // Description
        VStack(spacing: 12) {
          Text("Securely connect your accounts to get personalized financial insights and manage your money in one place.")
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

          Text("Your data is encrypted and protected with bank-level security.")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal)

        if linkedStateUnconfirmed {
          Label(
            "We couldn't confirm your linked accounts right now. If you've connected a bank before, it may already be linked.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.subheadline)
          .foregroundColor(.orange)
          .padding(.horizontal)
          .accessibilityLabel("Warning: we couldn't confirm your linked accounts right now. If you've connected a bank before, it may already be linked.")
        }

        if !alreadyLinked.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Already connected")
              .font(.headline)
              .accessibilityAddTraits(.isHeader)
            ForEach(alreadyLinked, id: \.self) { name in
              HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
                Text(name)
                  .font(.body)
              }
              .accessibilityElement(children: .combine)
              .accessibilityLabel("\(name), already connected")
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
          .background(Color.haloSecondaryBackground)
          .cornerRadius(12)
          .padding(.horizontal)
        }

        Spacer(minLength: 20)

        // Start button
        Button(action: {
          if alreadyLinked.isEmpty {
            action()
          } else {
            showingRelinkConfirmation = true
          }
        }) {
          HStack(spacing: 12) {
            Image(systemName: "arrow.right.circle.fill")
              .font(.headline)
            Text(alreadyLinked.isEmpty ? "Start Connection" : "Link Another Account")
              .font(.headline)
              .fontWeight(.semibold)
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 56)
          .background(Color.accentColor)
          .cornerRadius(16)
        }
        .accessibilityLabel(alreadyLinked.isEmpty ? "Start bank connection" : "Link another account")
        .accessibilityHint("Opens secure bank connection interface")
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
      }
      .padding(.top, 20)
    }
    .confirmationDialog(
      "Some banks are already connected",
      isPresented: $showingRelinkConfirmation,
      titleVisibility: .visible
    ) {
      Button("Continue") { action() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("\(alreadyLinked.joined(separator: ", ")) \(alreadyLinked.count == 1 ? "is" : "are") already connected. Connecting the same bank again can duplicate your accounts. Continue only to add a different bank or account.")
    }
  }
}
