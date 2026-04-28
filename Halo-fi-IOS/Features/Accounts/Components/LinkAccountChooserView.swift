//
//  LinkAccountChooserView.swift
//  Halo-fi-IOS
//
//  Sheet shown when the user taps "Link New Account" or the "+" toolbar
//  button in the Accounts views. Two paths from here:
//    1. Connect with Plaid — pushes the existing PlaidOnboardingView.
//    2. Add Manual Account — Phase 2; shows a "Coming soon" stub for now.
//
//  Sheet rather than navigationDestination(isPresented:) because the
//  latter caused layout-cycle freezes when nested inside another
//  navigationDestination(for:) (Settings → Accounts → Plaid).
//

import SwiftUI

struct LinkAccountChooserView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 12) {
          chooserOption(
            icon: "lock.shield.fill",
            iconTint: .blue,
            title: "Connect with Plaid",
            subtitle: "Securely link your bank in seconds. Balances and transactions update automatically.",
            destination: .plaid
          )

          chooserOption(
            icon: "square.and.pencil",
            iconTint: .teal,
            title: "Add Manual Account",
            subtitle: "Track an account that isn't on Plaid. You'll update the balance yourself.",
            destination: .manual
          )

          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
      }
      .navigationTitle("Add Account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cancel") { dismiss() }
            .foregroundColor(.white)
        }
      }
      .navigationDestination(for: ChooserDestination.self) { destination in
        switch destination {
        case .plaid:
          PlaidOnboardingView(
            onComplete: { dismiss() },
            onBack: { dismiss() }
          )
          .navigationBarTitleDisplayMode(.inline)
        case .manual:
          ManualAccountFormView()
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  private func chooserOption(
    icon: String,
    iconTint: Color,
    title: String,
    subtitle: String,
    destination: ChooserDestination
  ) -> some View {
    NavigationLink(value: destination) {
      HStack(spacing: 16) {
        Image(systemName: icon)
          .font(.title2)
          .foregroundColor(iconTint)
          .frame(width: 36, height: 36)

        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.body)
            .fontWeight(.semibold)
            .foregroundColor(.white)

          Text(subtitle)
            .font(.caption)
            .foregroundColor(.gray)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .foregroundColor(.gray)
          .font(.caption)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .background(Color.gray.opacity(0.1))
      .cornerRadius(16)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityHint(subtitle)
  }
}

private enum ChooserDestination: Hashable {
  case plaid
  case manual
}

#Preview {
  LinkAccountChooserView()
    .environment(UserManager())
    .environment(BankDataManager())
    .environment(PlaidManager())
}
