//
//  VoiceControlButton.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct VoiceControlButton: View {
  let icon: String
  let title: String
  let gradient: LinearGradient
  let strokeGradient: LinearGradient
  let onTap: () -> Void
  
  var body: some View {
    Button(action: onTap) {
      VStack(spacing: 8) {
        Image(systemName: icon)
          .font(.system(size: 30))
          .foregroundColor(.white)
        Text(title)
          .font(.headline)
          .foregroundColor(.white)
      }
      .frame(width: 100, height: 100)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(gradient)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(strokeGradient, lineWidth: 3)
      )
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    HStack(spacing: 40) {
      VoiceControlButton(
        icon: "mic.fill",
        title: "Mute",
        gradient: LinearGradient(
          colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        strokeGradient: LinearGradient(
          colors: [Color.blue, Color.purple],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      ) {}
      
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
      ) {}
    }
  }
}
