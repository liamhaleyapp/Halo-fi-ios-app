//
//  HomeView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct HomeView: View {
    @State private var showingConversation = false
    @State private var initialPrompt: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 10) {
                    // Voice conversation button - opens unified ConversationView
                    VoiceConversationButton {
                        initialPrompt = nil
                        showingConversation = true
                    }

                    // Quick action buttons
                    ActionButtonsSection(onAction: { prompt in
                        initialPrompt = prompt
                        showingConversation = true
                    })
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showingConversation) {
                ConversationView(initialPrompt: initialPrompt)
                    .navigationBarHidden(true)
            }
            // Phase 12 — accept cross-tab quick-action requests. The
            // Budget tab posts .askHaloRequested with a userInfo
            // prompt; MainTabView switches to tab 0 in parallel, so by
            // the time this fires HomeView is already on screen.
            .onReceive(NotificationCenter.default.publisher(for: .askHaloRequested)) { notification in
                let prompt = notification.userInfo?["prompt"] as? String
                initialPrompt = (prompt?.isEmpty == false) ? prompt : nil
                showingConversation = true
            }
        }
    }
}

#Preview {
    HomeView()
}
