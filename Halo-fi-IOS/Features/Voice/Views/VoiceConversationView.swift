//
//  VoiceCoversationView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct VoiceConversationView: View {
  @Environment(\.presentationMode) var presentationMode
  @State private var isMuted = false
  @State private var isListening = true
  
  var body: some View {
    ZStack {
      // Dark background
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 0) {
        // Header text at top
        VoiceHeader()
        
        Spacer()
        
        // Central animated graphics
        VoiceAnimationView()
        
        // Status text below mic graphic
        VoiceStatusText(isListening: isListening)
        
        Spacer()
        
        // Control buttons at bottom
        VoiceControlButtons(
          isMuted: isMuted,
          onMuteToggle: {
            isMuted.toggle()
            isListening.toggle()
          },
          onEndCall: {
            presentationMode.wrappedValue.dismiss()
          }
        )
      }
    }
    .navigationBarHidden(true)
  }
}

#Preview {
  VoiceConversationView()
}
