//
//  SettingsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

enum SettingsDestination: Hashable {
  case profile, preferences, subscription, inviteFriends, about, accounts
}

struct SettingsView: View {
  @Environment(UserManager.self) private var userManager
  @Environment(SubscriptionService.self) private var subscriptionService

  @State private var showLogoutConfirmation = false
  @State private var isLoggingOut = false
  @State private var showDeleteAccountConfirmation = false
  @State private var showDeleteAccountFinalConfirmation = false
  @State private var isDeletingAccount = false

  var body: some View {
    NavigationStack {
      ZStack {
        Color(.systemBackground).ignoresSafeArea()

        ScrollView {
          VStack(spacing: 8) {
            NavigationLink(value: SettingsDestination.profile) {
              SettingsOptionLabel(icon: "person.fill", title: "Profile")
            }

            NavigationLink(value: SettingsDestination.preferences) {
              SettingsOptionLabel(icon: "hexagon.fill", title: "Preferences")
            }

            NavigationLink(value: SettingsDestination.subscription) {
              SettingsOptionLabel(icon: "diamond.fill", title: "Subscription")
            }

            NavigationLink(value: SettingsDestination.inviteFriends) {
              SettingsOptionLabel(icon: "person.2.fill", title: "Invite Friends")
            }

            NavigationLink(value: SettingsDestination.accounts) {
              SettingsOptionLabel(icon: "building.2.fill", title: "Manage Linked Accounts")
            }

            NavigationLink(value: SettingsDestination.about) {
              SettingsOptionLabel(icon: "info.circle.fill", title: "About")
            }

            SettingsOption(
              icon: "rectangle.portrait.and.arrow.right",
              title: "Logout",
              action: {
                showLogoutConfirmation = true
              }
            )

#if DEBUG || TESTFLIGHT
            // Build Info Banner
            Divider()
              .padding(.vertical, 8)

            Text(AppEnvironment.buildTypeDescription)
              .font(.caption)
              .foregroundColor(AppEnvironment.isProdPlaid ? .red : .orange)
              .fontWeight(.bold)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 4)

            #if DEBUG
            SettingsOption(
              icon: "arrow.counterclockwise",
              title: "Reset Onboarding",
              action: {
                userManager.resetOnboarding()
              }
            )
            #endif
#endif

            SettingsOption(
              icon: "trash.fill",
              title: "Delete Account",
              action: {
                showDeleteAccountConfirmation = true
              }
            )
          }
          .padding(.horizontal, 20)
          .padding(.top, 20)
          .padding(.bottom, 100)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.large)
      .navigationDestination(for: SettingsDestination.self) { destination in
        switch destination {
        case .profile:
          ProfileView()
            .environment(userManager)

        case .preferences:
          PreferencesView()

        case .subscription:
          let viewModel = SubscriptionViewModel(subscriptionService: subscriptionService)
          SubscriptionView(viewModel: viewModel)

        case .inviteFriends:
          InviteFriendsView()

        case .about:
          AboutView()

        case .accounts:
          AccountsView()
        }
      }
    }
    .alert("Log Out", isPresented: $showLogoutConfirmation) {
      Button("Cancel", role: .cancel) { }
      Button("Log Out", role: .destructive) {
        performLogout()
      }
    } message: {
      Text("Are you sure you want to log out?")
    }
    .alert("Delete Account", isPresented: $showDeleteAccountConfirmation) {
      Button("Cancel", role: .cancel) { }
      Button("Continue", role: .destructive) {
        showDeleteAccountFinalConfirmation = true
      }
    } message: {
      Text("This will permanently delete your account and all associated data. This action cannot be undone.")
    }
    .alert("Are you absolutely sure?", isPresented: $showDeleteAccountFinalConfirmation) {
      Button("Cancel", role: .cancel) { }
      Button("Delete My Account", role: .destructive) {
        Task {
          await performDeleteAccount()
        }
      }
    } message: {
      Text("All your data, linked banks, and account history will be permanently removed. This cannot be reversed.")
    }
    .loadingOverlay(isLoading: isLoggingOut, message: "Logging out...")
    .loadingOverlay(isLoading: isDeletingAccount, message: "Deleting account...")
  }

  private func performLogout() {
    isLoggingOut = true
    // Brief delay for visual feedback before the view transitions
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      subscriptionService.clearCachedState()
      userManager.signOut()
      isLoggingOut = false
    }
  }

  private func performDeleteAccount() async {
    guard let userId = userManager.currentUser?.id else { return }

    isDeletingAccount = true
    do {
      try await AuthService.shared.deleteAccount(userId: userId)
      isDeletingAccount = false

      // Clear all local state for deleted user
      userManager.resetOnboarding()
      subscriptionService.clearCachedState()
      userManager.signOut()
    } catch {
      isDeletingAccount = false
      Logger.error("Failed to delete account: \(error)")
    }
  }
}

/// Label-only view for NavigationLink styling
private struct SettingsOptionLabel: View {
  let icon: String
  let title: String

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundColor(.blue)
        .frame(width: 28, height: 28)

      Text(title)
        .font(.body)
        .fontWeight(.medium)
        .foregroundColor(.primary)

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(.gray)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(12)
  }
}

#Preview {
  SettingsView()
    .environment(UserManager())
    .environment(SubscriptionService())
}
