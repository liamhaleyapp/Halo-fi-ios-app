//
//  HomeView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct HomeView: View {
  @Environment(UserManager.self) private var userManager
  @State private var showingConversation = false

  #if DEBUG
  @State private var showingLegacyVoice = false
  @State private var showingLegacyChat = false
  #endif

  private var userName: String {
    userManager.currentUser?.firstName ?? "User"
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Color(.systemBackground).ignoresSafeArea()

        VStack(spacing: 10) {
          // Header
          HomeHeader(userName: userName)

          // Voice conversation button - opens unified ConversationView
          VoiceConversationButton {
            showingConversation = true
          }

          #if DEBUG
          // Legacy views for comparison testing
          VStack(spacing: 8) {
            Button(action: {
              showingLegacyVoice = true
            }) {
              HStack {
                Image(systemName: "mic.circle")
                Text("Legacy Voice View")
              }
              .frame(maxWidth: .infinity)
              .padding()
              .background(Color.gray.opacity(0.3))
              .foregroundColor(.primary)
              .cornerRadius(12)
            }

            Button(action: {
              showingLegacyChat = true
            }) {
              HStack {
                Image(systemName: "message.circle")
                Text("Legacy Chat View")
              }
              .frame(maxWidth: .infinity)
              .padding()
              .background(Color.gray.opacity(0.3))
              .foregroundColor(.primary)
              .cornerRadius(12)
            }
          }
          .padding(.horizontal, 20)
          #endif

          // Action buttons
          ActionButtonsSection()
        }
      }
    }
    .navigationBarHidden(true)
    .fullScreenCover(isPresented: $showingConversation) {
      ConversationView()
    }
    #if DEBUG
    .fullScreenCover(isPresented: $showingLegacyVoice) {
      VoiceConversationView()
    }
    .sheet(isPresented: $showingLegacyChat) {
      AgentChatView()
    }
    #endif
  }
}

#Preview {
  HomeView()
}
