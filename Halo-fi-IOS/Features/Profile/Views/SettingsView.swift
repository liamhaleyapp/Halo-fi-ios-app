//
//  SettingsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

enum SettingsDestination: Hashable {
  case profile, preferences, subscription, inviteFriends, about, accounts, contactUs
}

struct SettingsView: View {
  @Environment(UserManager.self) private var userManager
  @Environment(SubscriptionService.self) private var subscriptionService

  @State private var showLogoutConfirmation = false
  @State private var isLoggingOut = false
  @State private var showDeleteAccountConfirmation = false
  @State private var showDeleteAccountFinalConfirmation = false
  @State private var isDeletingAccount = false
  // Temporary debug — voice-minute reset button. Drop the state +
  // the SettingsOption when minute-quota UX is finalized.
  @State private var isResettingMinutes = false
  @State private var resetMinutesAlert: ResetMinutesAlert?

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

            NavigationLink(value: SettingsDestination.contactUs) {
              SettingsOptionLabel(icon: "envelope.fill", title: "Contact Us")
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

            // Temporary admin-only "Reset Voice Minutes" — calls the
            // backend's /agent/admin/reset-minutes endpoint, which
            // clears the Redis counter that was rate-limiting voice
            // sessions during dev. Drop this once minute-quota UX
            // is finalized.
            SettingsOption(
              icon: "mic.slash.fill",
              title: isResettingMinutes ? "Resetting…" : "Reset Voice Minutes",
              action: { Task { await performResetMinutes() } }
            )
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
          SubscriptionManagementView()

        case .inviteFriends:
          InviteFriendsView()

        case .about:
          AboutView()

        case .accounts:
          AccountsView()

        case .contactUs:
          ContactUsView()
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
    .alert(item: $resetMinutesAlert) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
      )
    }
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

  /// Hits the admin-only /agent/admin/reset-minutes endpoint to
  /// clear the Redis voice-minute counter so we can keep testing
  /// without hitting the per-period cap. Backend rejects with 403
  /// if the user's email isn't in ADMIN_EMAILS.
  private func performResetMinutes() async {
    isResettingMinutes = true
    defer { isResettingMinutes = false }
    do {
      let _: EmptyResponse = try await NetworkService.shared.authenticatedRequest(
        endpoint: APIEndpoints.Agent.resetMinutes,
        method: .POST,
        body: nil,
        responseType: EmptyResponse.self
      )
      Haptics.success()
      resetMinutesAlert = ResetMinutesAlert(
        title: "Voice Minutes Reset",
        message: "Your voice-minute counter is back to zero. You can use the agent again."
      )
    } catch {
      Haptics.error()
      resetMinutesAlert = ResetMinutesAlert(
        title: "Couldn't Reset",
        message: "\(error.localizedDescription)\n\nMake sure your email is in the ADMIN_EMAILS env var on Railway."
      )
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

/// Drives the success/failure alert for the debug "Reset Voice
/// Minutes" button. Identifiable so SwiftUI can present via
/// `.alert(item:)`.
private struct ResetMinutesAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
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
