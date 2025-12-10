//
//  VoiceCoversationView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct VoiceConversationView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(UserManager.self) private var userManager
  private let voiceService = VoiceService.shared
  
  @State private var isMuted = false
  @State private var isListening = true
  @State private var showingError = false
  @State private var errorMessage = ""
  
  private var isConnected: Bool {
    voiceService.isConnected
  }
  
  private var isRecording: Bool {
    voiceService.isRecording
  }
  
  var body: some View {
    ZStack {
      Color(.systemBackground).ignoresSafeArea()
      
      VStack(spacing: 0) {
        VoiceHeader()
        
        Spacer()
        
        VoiceAnimationView(isRecording: isRecording, isConnected: isConnected)
        
        VoiceStatusText(
          isListening: isListening && !isMuted
        )
        
        Spacer()
        
        VoiceControlButtons(
          isMuted: isMuted,
          onMuteToggle: { handleMuteToggle() },
          onEndCall: { handleEndCall() }
        )
      }
    }
    .navigationBarHidden(true)
    .onAppear {
      Task { await connectToVoiceService() }
    }
    .onDisappear {
      Task { await disconnectFromVoiceService() }
    }
    .alert("Voice Chat Error", isPresented: $showingError) {
      Button("OK") { }
    } message: {
      Text(errorMessage)
    }
  }
  
  // MARK: - Actions
  
  private func handleMuteToggle() {
    isMuted.toggle()
    isListening.toggle()
    
    if isMuted {
      voiceService.stopRecording()
    } else {
      Task {
        do {
          try await voiceService.startRecording()
        } catch {
          await MainActor.run {
            errorMessage = error.localizedDescription
            showingError = true
          }
        }
      }
    }
  }
  
  private func handleEndCall() {
    Task {
      await disconnectFromVoiceService()
      dismiss()
    }
  }
  
  private func connectToVoiceService() async {
    guard let userId = userManager.currentUser?.id else {
      await MainActor.run {
        errorMessage = "User not authenticated"
        showingError = true
      }
      return
    }
    
    do {
      try await voiceService.connect(userId: userId)
      try await voiceService.startRecording()
    } catch {
      await MainActor.run {
        errorMessage = error.localizedDescription
        showingError = true
      }
    }
  }
  
  private func disconnectFromVoiceService() async {
    voiceService.stopRecording()
    voiceService.disconnect()
  }
}

#Preview {
  VoiceConversationView()
}
