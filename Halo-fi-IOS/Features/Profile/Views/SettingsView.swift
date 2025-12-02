//
//  SettingsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

enum SettingsDestination: Identifiable {
  case profile, preferences, subscription, inviteFriends, about, accounts, webSocketTest
  
  var id: String {
    switch self {
    case .profile: return "profile"
    case .preferences: return "preferences"
    case .subscription: return "subscription"
    case .inviteFriends: return "inviteFriends"
    case .about: return "about"
    case .accounts: return "accounts"
    case .webSocketTest: return "webSocketTest"
    }
  }
}

struct SettingsView: View {
  @Environment(UserManager.self) private var userManager
  @Environment(SubscriptionService.self) private var subscriptionService
  
  @State private var destination: SettingsDestination?
  
#if DEBUG
  @State private var showingWebSocketTest = false
#endif
  
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
              icon: "person.fill",
              title: "Accounts",
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
                userManager.signOut()
              }
            )
            
#if DEBUG
            // Debug Section
            Divider()
              .padding(.vertical, 8)
            
            Text("DEBUG")
              .font(.caption)
              .foregroundColor(.orange)
              .fontWeight(.bold)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 4)
            
            SettingsOption(
              icon: "network",
              title: "WebSocket Test",
              action: {
                showingWebSocketTest = true
              }
            )
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
        
      case .webSocketTest:
        WebSocketTestView()
      }
    }
  }
}

#Preview {
  SettingsView()
    .environment(UserManager())
    .environment(SubscriptionService())
}
