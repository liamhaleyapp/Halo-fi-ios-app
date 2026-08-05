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
                .readableContentWidth()
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showingConversation) {
                ConversationView(initialPrompt: initialPrompt)
                    .navigationBarHidden(true)
            }
            // Tell MainTabView the conversation closed so it can return
            // the user to whichever tab launched the conversation. We
            // can't observe ConversationView's onDisappear (fires for
            // backgrounding too) — watching the binding flip true→false
            // is the correct user-driven dismiss signal.
            .onChange(of: showingConversation) { _, isPresented in
                if !isPresented {
                    NotificationCenter.default.post(
                        name: .conversationDismissed,
                        object: nil
                    )
                }
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
