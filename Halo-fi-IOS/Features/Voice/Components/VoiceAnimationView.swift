//
//  VoiceAnimationView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct VoiceAnimationView: View {
  let isRecording: Bool
  let isConnected: Bool
  
  @State private var pulseScale: CGFloat = 1.0
  @State private var rotationAngle: Double = 0.0
  
  var body: some View {
    ZStack {
      // Outer pulsing circle
      Circle()
        .fill(
          LinearGradient(
            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .frame(width: 200, height: 200)
        .scaleEffect(pulseScale)
        .opacity(0.6)
        .animation(
          Animation.easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true),
          value: pulseScale
        )
      
      // Middle rotating ring
      Circle()
        .stroke(
          LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 3
        )
        .frame(width: 160, height: 160)
        .rotationEffect(.degrees(rotationAngle))
        .animation(
          Animation.linear(duration: 8.0)
            .repeatForever(autoreverses: false),
          value: rotationAngle
        )
      
      // Inner microphone icon
      Image(systemName: "mic.fill")
        .font(.system(size: 60))
        .foregroundColor(.white)
        .frame(width: 120, height: 120)
        .background(
          Circle()
            .fill(
              LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
        )
        .overlay(
          Circle()
            .stroke(
              LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              lineWidth: 4
            )
        )
        .shadow(color: .blue.opacity(0.5), radius: 30, x: 0, y: 0)
    }
    .onAppear {
      // Start animations
      pulseScale = 1.2
      rotationAngle = 360
    }
    .onChange(of: isRecording) { _, newValue in
      if newValue {
        // Start more intense animation when recording
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
          pulseScale = 1.4
        }
      } else {
        // Return to normal animation when not recording
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
          pulseScale = 1.2
        }
      }
    }
    .onChange(of: isConnected) { _, newValue in
      if !newValue {
        // Stop animations when disconnected
        pulseScale = 1.0
        rotationAngle = 0.0
      }
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VoiceAnimationView(isRecording: false, isConnected: true)
  }
}
