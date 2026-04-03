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
                    HaloFiLogo(size: 60)

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
        }
    }
}

#Preview {
    HomeView()
}
