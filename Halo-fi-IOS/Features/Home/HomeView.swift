//
//  HomeView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct HomeView: View {
  @Environment(UserManager.self) private var userManager
  @State private var showingVoiceConversation = false
  @State private var showingAgentChat = false
  
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
          
          // Voice conversation button
          VoiceConversationButton {
            showingVoiceConversation = true
          }
          
          // Test Agent Chat Button (for testing)
          #if DEBUG
          Button(action: {
            showingAgentChat = true
          }) {
            HStack {
              Image(systemName: "message.circle.fill")
              Text("Test Agent Chat")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(12)
          }
          .padding(.horizontal, 20)
          #endif
          
          // Action buttons
          ActionButtonsSection()
        }
      }
    }
    .navigationBarHidden(true)
    .fullScreenCover(isPresented: $showingVoiceConversation) {
      VoiceConversationView()
    }
    .sheet(isPresented: $showingAgentChat) {
      AgentChatView()
    }
  }
}

#Preview {
  HomeView()
}
