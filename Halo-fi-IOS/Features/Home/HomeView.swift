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
  
  private var userName: String {
    userManager.currentUser?.firstName ?? "User"
  }
  
  var body: some View {
    NavigationView {
      ZStack {
        // Dark background
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 10) {
          // Header
          HomeHeader(userName: userName)
          
          // Voice conversation button
          VoiceConversationButton {
            showingVoiceConversation = true
          }
          
          // Action buttons
          ActionButtonsSection()
        }
      }
    }
    .navigationBarHidden(true)
    .fullScreenCover(isPresented: $showingVoiceConversation) {
      VoiceConversationView()
    }
  }
}

#Preview {
  HomeView()
}
