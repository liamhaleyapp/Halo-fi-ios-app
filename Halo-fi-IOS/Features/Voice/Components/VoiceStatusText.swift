//
//  VoiceStatusText.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct VoiceStatusText: View {
  let isListening: Bool
  
  var body: some View {
    Text(isListening ? "Listening..." : "Muted")
      .font(.title2)
      .fontWeight(.medium)
      .foregroundColor(.primary)
      .padding(.top, 30)
      .opacity(isListening ? 1.0 : 0.7)
  }
}

#Preview {
  ZStack {
    Color(.systemBackground).ignoresSafeArea()
    VStack {
      VoiceStatusText(isListening: true)
      VoiceStatusText(isListening: false)
    }
  }
}
