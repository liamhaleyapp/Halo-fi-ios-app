//
//  SettingsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

enum SettingsDestination: Identifiable {
  case profile, preferences, subscription, inviteFriends, about, accounts

  var id: String {
    switch self {
    case .profile: return "profile"
    case .preferences: return "preferences"
    case .subscription: return "subscription"
    case .inviteFriends: return "inviteFriends"
    case .about: return "about"
    case .accounts: return "accounts"
    }
  }
}

struct SettingsView: View {
  @Environment(UserManager.self) private var userManager
  @Environment(SubscriptionService.self) private var subscriptionService

  @State private var destination: SettingsDestination?
  @State private var showLogoutConfirmation = false
  @State private var isLoggingOut = false
  @State private var showDeleteAccountConfirmation = false
  @State private var isDeletingAccount = false

  var body: some View {
    NavigationStack {
      ZStack {
        Color(.systemBackground).ignoresSafeArea()
        
        ScrollView {
          VStack(spacing: 8) {
            SettingsOption(
              icon: "person.fill",
              title: "Profile",
              action: {
                destination = .profile
              }
            )
            
            SettingsOption(
              icon: "hexagon.fill",
              title: "Preferences",
              action: {
                destination = .preferences
              }
            )
            
            SettingsOption(
              icon: "diamond.fill",
              title: "Subscription",
              action: {
                destination = .subscription
              }
            )
            
            SettingsOption(
              icon: "person.2.fill",
              title: "Invite Friends",
              action: {
                destination = .inviteFriends
              }
            )
            
            SettingsOption(
              icon: "building.2.fill",
              title: "Manage Banks",
              action: {
                destination = .accounts
              }
            )
            
            SettingsOption(
              icon: "info.circle.fill",
              title: "About",
              action: {
                destination = .about
              }
            )
            
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

            SettingsOption(
              icon: "trash.fill",
              title: "Delete Account",
              action: {
                showDeleteAccountConfirmation = true
              }
            )
            #endif
#endif
          }
          .padding(.horizontal, 20)
          .padding(.top, 20)
          .padding(.bottom, 100)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.large)
    }
    .fullScreenCover(item: $destination) { dest in
      switch dest {
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
      Button("Delete", role: .destructive) {
        Task {
          await performDeleteAccount()
        }
      }
    } message: {
      Text("This will permanently delete your account and all associated data. This action cannot be undone.")
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

#Preview {
  SettingsView()
    .environment(UserManager())
    .environment(SubscriptionService())
}
