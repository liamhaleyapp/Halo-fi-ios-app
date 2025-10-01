//
//  VoiceConversationButton.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct VoiceConversationButton: View {
  let onTap: () -> Void
  
  var body: some View {
    VStack(spacing: 16) {
      Button(action: onTap) {
        ZStack {
          Circle()
            .fill(
              LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(width: 120, height: 120)
            .overlay(
              Circle()
                .stroke(
                  LinearGradient(
                    colors: [Color.blue, Color.purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                  ),
                  lineWidth: 3
                )
            )
            .shadow(color: .blue.opacity(0.5), radius: 20, x: 0, y: 0)
          
          // Mic icon for voice conversation
          Image(systemName: "mic.fill")
            .font(.system(size: 50, weight: .medium))
            .foregroundColor(.white)
        }
      }
      
      Text("Tap to start conversation")
        .font(.headline)
        .foregroundColor(.white)
    }
    .padding(80)
    .overlay(
      RoundedRectangle(cornerRadius: 20)
        .stroke(
          LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 2
        )
    )
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VoiceConversationButton(onTap: {})
  }
}
