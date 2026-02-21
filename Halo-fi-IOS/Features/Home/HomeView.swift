//
//  HomeView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct HomeView: View {
  @State private var showingConversation = false

  var body: some View {
    NavigationStack {
      ZStack {
        Color(.systemBackground).ignoresSafeArea()

        VStack(spacing: 10) {
          // Voice conversation button - opens unified ConversationView
          VoiceConversationButton {
            showingConversation = true
          }

          // Action buttons
          ActionButtonsSection()
        }
      }
      .navigationBarHidden(true)
      .navigationDestination(isPresented: $showingConversation) {
        ConversationView()
          .navigationBarHidden(true)
      }
    }
  }
}

#Preview {
  HomeView()
}
