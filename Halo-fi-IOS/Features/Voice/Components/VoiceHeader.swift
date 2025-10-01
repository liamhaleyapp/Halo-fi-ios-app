//
//  VoiceHeader.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct VoiceHeader: View {
  var body: some View {
    Text("Hi, I'm Halo. How can I help you?")
      .font(.title2)
      .fontWeight(.medium)
      .foregroundColor(.white)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 40)
      .padding(.top, 60)
      .padding(.bottom, 20)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VoiceHeader()
  }
}
