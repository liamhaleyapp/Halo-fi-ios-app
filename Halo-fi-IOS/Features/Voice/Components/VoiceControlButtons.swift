//
//  VoiceControlButtons.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct VoiceControlButtons: View {
  let isMuted: Bool
  let onMuteToggle: () -> Void
  let onEndCall: () -> Void
  
  private var muteButtonGradient: LinearGradient {
    LinearGradient(
      colors: isMuted ?
        [Color.orange.opacity(0.8), Color.red.opacity(0.8)] :
        [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
  
  private var muteButtonStrokeGradient: LinearGradient {
    LinearGradient(
      colors: isMuted ?
        [Color.orange, Color.red] :
        [Color.blue, Color.purple],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
  
  var body: some View {
    HStack(spacing: 40) {
      // Mute button
      VoiceControlButton(
        icon: isMuted ? "mic.slash.fill" : "mic.fill",
        title: isMuted ? "Unmute" : "Mute",
        gradient: muteButtonGradient,
        strokeGradient: muteButtonStrokeGradient
      ) {
        onMuteToggle()
      }
      
      // End button
      VoiceControlButton(
        icon: "phone.down.fill",
        title: "End",
        gradient: LinearGradient(
          colors: [Color.red.opacity(0.8), Color.pink.opacity(0.8)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        strokeGradient: LinearGradient(
          colors: [Color.red, Color.pink],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      ) {
        onEndCall()
      }
    }
    .padding(.bottom, 50)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VoiceControlButtons(
      isMuted: false,
      onMuteToggle: {},
      onEndCall: {}
    )
  }
}
