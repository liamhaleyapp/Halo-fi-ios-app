//
//  SettingsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI
import LocalAuthentication

enum SettingsDestination: Hashable {
  case profile, preferences, accessibility, benefitsProfile, moneyProfile, counselorQuestions, fieldOffice, workProfile, subscription, inviteFriends, about, accounts, contactUs, aiDataSharing
}

struct SettingsView: View {
  @Environment(UserManager.self) private var userManager
  @Environment(SubscriptionService.self) private var subscriptionService
  @Environment(DIContainer.self) private var container

  @State private var showLogoutConfirmation = false
  @State private var isLoggingOut = false
  @State private var showDeleteAccountConfirmation = false
  @State private var showDeleteAccountFinalConfirmation = false
  @State private var isDeletingAccount = false
  @State private var deleteAccountFailed = false

  /// Mirrors `biometricCredentialStore.hasEnrolledCredentials` so the Toggle
  /// stays in sync. Re-read in .onAppear.
  @State private var biometricEnrolled = false
  @State private var showBiometricEnrollSheet = false

  // Refresh from bank (metered, 2026-09-06)
  @Environment(BankDataManager.self) private var bankDataManager
  @Environment(BudgetDataManager.self) private var budgetDataManager
  @State private var refreshStatus: ManualRefreshStatus?
  @State private var showRefreshConfirm = false
  @State private var showRefreshExhausted = false
  @State private var isRefreshingFromBank = false
  @State private var refreshMessage: String?
  // Temporary debug — voice-minute reset button. Drop the state +
  // the SettingsOption when minute-quota UX is finalized.
  @State private var isResettingMinutes = false
  @State private var resetMinutesAlert: ResetMinutesAlert?
  /// Bound to the NavigationStack so we can clear it when MainTabView
  /// posts .resetSettingsNavigation — keeps re-entry at the root list
  /// rather than wherever the user was nested when they left.
  @State private var navigationPath = NavigationPath()

  var body: some View {
    NavigationStack(path: $navigationPath) {
      ZStack {
        Color(.systemBackground).ignoresSafeArea()

        ScrollView {
          VStack(spacing: 8) {
            TabTitle("Settings", spokenAsHeader: true)
            NavigationLink(value: SettingsDestination.profile) {
              SettingsOptionLabel(icon: "person.fill", title: "Profile")
            }

            NavigationLink(value: SettingsDestination.preferences) {
              SettingsOptionLabel(icon: "hexagon.fill", title: "Preferences")
            }

            // WP4 — haptic intensity, speech verbosity, VoiceOver ducking.
            NavigationLink(value: SettingsDestination.accessibility) {
              SettingsOptionLabel(icon: "figure.walk.motion", title: "Accessibility")
            }

            // Benefits profile (Sep-2026): the answers that drive every
            // benefit-specific screen. For users without a Benefits tab
            // (answered no SSI / no SSDI, or not answered yet) this is the
            // way in: "Set up benefits" brings the tab back.
            NavigationLink(value: SettingsDestination.benefitsProfile) {
              SettingsOptionLabel(
                icon: userManager.capabilities.showsBenefitsLane ? "heart.text.square.fill" : "plus.circle.fill",
                title: userManager.capabilities.showsBenefitsLane ? "Benefits profile" : "Set up benefits"
              )
            }

            // Money profile (2026-09-05): housing, goal, money style, stress.
            NavigationLink(value: SettingsDestination.moneyProfile) {
              SettingsOptionLabel(icon: "person.text.rectangle.fill",
                                  title: userManager.capabilities.moneyProfileRemaining > 0 ? "Finish setting up" : "Money profile")
            }

            // WP3 — expenses flagged "Not sure this counts? Ask my counselor".
            NavigationLink(value: SettingsDestination.counselorQuestions) {
              SettingsOptionLabel(icon: "questionmark.bubble.fill", title: "Questions for my counselor")
            }

            // WP6 — how the field office receives the monthly package.
            NavigationLink(value: SettingsDestination.fieldOffice) {
              SettingsOptionLabel(icon: "building.columns.fill", title: "My field office")
            }

            // Drives BWE/IRWE classifier accuracy. Shown for everyone;
            // copy inside the view explains it's primarily for SSI users
            // with earned income.
            NavigationLink(value: SettingsDestination.workProfile) {
              SettingsOptionLabel(icon: "briefcase.fill", title: "Work Profile")
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

            // The paid bank refresh, chosen on purpose with a visible count.
            SettingsOption(
              icon: "arrow.clockwise.circle.fill",
              title: isRefreshingFromBank ? "Refreshing from your banks…" : "Refresh from bank",
              action: { askToRefreshFromBank() }
            )
            .disabled(isRefreshingFromBank)
            .accessibilityHint("Asks your banks for today's balances and transactions. Counts against your monthly manual refreshes.")
            if let refreshMessage {
              Text(refreshMessage)
                .font(.footnote)
                .foregroundColor(.haloTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            }

            // Apple 5.1.1(i)/5.1.2(i): the disclosure of what we send to
            // the AI providers has to be reachable in-app at any time, not
            // only behind the one-time onboarding consent gate.
            NavigationLink(value: SettingsDestination.aiDataSharing) {
              SettingsOptionLabel(icon: "waveform.circle.fill", title: "AI & Data Sharing")
            }

            NavigationLink(value: SettingsDestination.contactUs) {
              SettingsOptionLabel(icon: "envelope.fill", title: "Contact Us")
            }

            NavigationLink(value: SettingsDestination.about) {
              SettingsOptionLabel(icon: "info.circle.fill", title: "About")
            }

            biometricToggleRow

            SettingsOption(
              icon: "rectangle.portrait.and.arrow.right",
              title: "Logout",
              action: {
                showLogoutConfirmation = true
              }
            )

#if DEBUG
            // Build Info Banner
            Divider()
              .padding(.vertical, 8)

            Text(AppEnvironment.buildTypeDescription)
              .font(.caption)
              .foregroundColor(AppEnvironment.isProdPlaid ? .red : .orange)
              .fontWeight(.bold)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 4)

            SettingsOption(
              icon: "arrow.counterclockwise",
              title: "Reset Onboarding",
              action: {
                userManager.resetOnboarding()
              }
            )

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
          .padding(.top, 12)
          .padding(.bottom, 100)
          .readableContentWidth()
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.hidden, for: .navigationBar)
      .onAppear {
        biometricEnrolled = signedInWithSocial ? BiometricAppLock.isEnabled : container.biometricCredentialStore.hasEnrolledCredentials
      }
      .navigationDestination(for: SettingsDestination.self) { destination in
        switch destination {
        case .profile:
          ProfileView()
            .environment(userManager)

        case .preferences:
          PreferencesView()

        case .accessibility:
          AccessibilitySettingsView()

        case .benefitsProfile:
          BenefitsProfileView()

        case .moneyProfile:
          ProfileQuestionsView(questions: ProfileQuestions.money, embeddedInOnboarding: false,
                               ignoreVisibility: true, onComplete: {})
            .navigationTitle("Money profile")

        case .counselorQuestions:
          CounselorQuestionsView()

        case .fieldOffice:
          FieldOfficeView()

        case .workProfile:
          WorkProfileView()

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

        case .aiDataSharing:
          AIDataSharingView()
            .environment(userManager)
        }
      }
      // MainTabView posts this when the user leaves the Settings
      // tab. Clearing the path here means re-entering always lands
      // on the root list — no leftover nested view from last time.
      .onReceive(NotificationCenter.default.publisher(for: .resetSettingsNavigation)) { _ in
        if !navigationPath.isEmpty {
          navigationPath.removeLast(navigationPath.count)
        }
      }
    }
    .alert("Refresh from bank", isPresented: $showRefreshConfirm, presenting: refreshStatus) { status in
      Button("Refresh") { runRefreshFromBank() }
      Button("Not now", role: .cancel) { }
    } message: { status in
      Text(status.confirmLine ?? "Refresh now?")
    }
    .alert("No manual refreshes left", isPresented: $showRefreshExhausted, presenting: refreshStatus) { _ in
      Button("OK", role: .cancel) { }
    } message: { status in
      Text(status.exhaustedLine)
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
      Text("Your app access will end now. Your data and linked banks will be removed, with cleanup continuing automatically. This cannot be reversed. Account deletion does not cancel an App Store subscription.")
    }
    .loadingOverlay(isLoading: isLoggingOut, message: "Logging out...")
    .loadingOverlay(isLoading: isDeletingAccount, message: "Requesting account deletion...")
    .alert("Could not confirm deletion", isPresented: $deleteAccountFailed) {
      Button("OK", role: .cancel) { }
    } message: {
      Text("We could not confirm your deletion request. Please try again. If the request reached us, cleanup will continue automatically.")
    }
    .alert(item: $resetMinutesAlert) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
      )
    }
    .sheet(isPresented: $showBiometricEnrollSheet) {
      BiometricSettingsEnrollmentSheet(
        email: userManager.currentUser?.email,
        biometryType: currentBiometryType,
        authService: container.authService,
        biometricAuthService: container.biometricAuthService,
        credentialStore: container.biometricCredentialStore
      ) { enrolled in
        if enrolled {
          biometricEnrolled = true
          // Mark as offered so the post-sign-in prompt doesn't reappear.
          UserDefaults.standard.set(true, forKey: "biometric_enrollment_offered")
        }
      }
    }
  }

  // MARK: - Biometric toggle

  private var currentBiometryType: LABiometryType {
    if case .available(let type) = container.biometricAuthService.currentStatus() {
      return type
    }
    return .none
  }

  private var biometryDisplayName: String {
    if case .available(let type) = container.biometricAuthService.currentStatus() {
      switch type {
      case .faceID: return "Face ID"
      case .touchID: return "Touch ID"
      default: return "biometrics"
      }
    }
    return "biometrics"
  }

  private var biometryIcon: String {
    if case .available(let type) = container.biometricAuthService.currentStatus(),
       type == .touchID {
      return "touchid"
    }
    return "faceid"
  }

  // MARK: - Refresh from bank

  private var planHint: String { ManualRefreshService.planHint(Array(subscriptionService.activeEntitlements)) }

  private func askToRefreshFromBank() {
    refreshMessage = nil
    Task { @MainActor in
      do {
        let status = try await ManualRefreshService.status(plan: planHint)
        refreshStatus = status
        if status.remaining > 0 { showRefreshConfirm = true } else { showRefreshExhausted = true }
      } catch {
        refreshMessage = "Couldn't check your refreshes right now. Try again in a moment."
        UIAccessibility.post(notification: .announcement, argument: refreshMessage ?? "")
      }
    }
  }

  private func runRefreshFromBank() {
    isRefreshingFromBank = true
    Task { @MainActor in
      defer { isRefreshingFromBank = false }
      do {
        let after = try await ManualRefreshService.run(plan: planHint)
        refreshStatus = after
        // The server already pulled from Plaid; now every screen re-reads.
        budgetDataManager.markStale()
        async let bank: () = bankDataManager.forceRefresh()
        async let budget: () = budgetDataManager.refresh()
        _ = await (bank, budget)
        refreshMessage = "Refreshed. Checked just now. \(after.remaining) of \(after.limit) manual refreshes left for \(after.monthLabel)."
        Haptics.success()
      } catch ManualRefreshError.exhausted {
        if let status = try? await ManualRefreshService.status(plan: planHint) { refreshStatus = status }
        showRefreshExhausted = true
      } catch {
        // A 429 the error parser could not classify still means "used up".
        if let status = try? await ManualRefreshService.status(plan: planHint), status.remaining == 0 {
          refreshStatus = status
          showRefreshExhausted = true
        } else {
          refreshMessage = "The refresh didn't finish. Your balances still update on their own each day."
          Haptics.error()
        }
      }
      UIAccessibility.post(notification: .announcement, argument: refreshMessage ?? "")
    }
  }

  @ViewBuilder
  private var biometricToggleRow: some View {
    if case .available = container.biometricAuthService.currentStatus() {
      HStack(spacing: 16) {
        Image(systemName: biometryIcon)
          .font(.title3)
          .foregroundColor(.blue)
          .frame(width: 28, height: 28)

        Text(signedInWithSocial ? "Unlock with \(biometryDisplayName)" : "Sign in with \(biometryDisplayName)")
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(.primary)

        Spacer()

        Toggle("", isOn: Binding(
          get: { biometricEnrolled },
          set: { newValue in handleBiometricToggle(newValue) }
        ))
        .labelsHidden()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(Color.haloSecondaryBackground)
      .cornerRadius(12)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Sign in with \(biometryDisplayName)")
      .accessibilityValue(biometricEnrolled ? "On" : "Off")
    }
  }

  /// Google / Apple accounts have no HaloFi password to store, so for them
  /// Face ID guards the app itself (an unlock) instead of re-signing in.
  private var signedInWithSocial: Bool {
    (UserDefaults.standard.string(forKey: "last_auth_provider") ?? "password") != "password"
  }

  private func handleBiometricToggle(_ newValue: Bool) {
    if signedInWithSocial {
      Task {
        if newValue {
          do {
            try await container.biometricAuthService.authenticate(reason: "Turn on \(biometryDisplayName) unlock")
            BiometricAppLock.isEnabled = true
            biometricEnrolled = true
            UIAccessibility.post(notification: .announcement, argument: "\(biometryDisplayName) unlock is on.")
          } catch {
            biometricEnrolled = false
          }
        } else {
          BiometricAppLock.isEnabled = false
          biometricEnrolled = false
          UIAccessibility.post(notification: .announcement, argument: "\(biometryDisplayName) unlock is off.")
        }
      }
      return
    }
    if newValue {
      // We don't have the user's password from current session — present the
      // enrollment sheet to collect + verify it, then save behind biometry.
      showBiometricEnrollSheet = true
      // Toggle stays off until the sheet's onComplete callback flips it.
      biometricEnrolled = false
    } else {
      container.biometricCredentialStore.clear()
      biometricEnrolled = false
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

    let generation = SessionLifetime.shared.current
    isDeletingAccount = true
    do {
      try await AuthService.shared.deleteAccount(userId: userId)
      guard SessionLifetime.shared.isCurrent(generation) else { return }
      isDeletingAccount = false

      // Clear all local state for deleted user
      userManager.resetOnboarding()
      subscriptionService.clearCachedState()
      container.biometricCredentialStore.clear()
      // Wipe last-auth-provider so the deleted user's preference doesn't
      // bias the SignInView for the next sign-in (e.g., a different account).
      UserDefaults.standard.removeObject(forKey: "last_auth_provider")
      userManager.signOut()
    } catch {
      guard SessionLifetime.shared.isCurrent(generation) else { return }
      isDeletingAccount = false
      deleteAccountFailed = true
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
        .foregroundColor(.haloTextSecondary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(Color.haloSecondaryBackground)
    .cornerRadius(12)
  }
}

#Preview {
  let container = DIContainer()
  return SettingsView()
    .environment(container)
    .environment(container.userManager)
    .environment(SubscriptionService())
}
