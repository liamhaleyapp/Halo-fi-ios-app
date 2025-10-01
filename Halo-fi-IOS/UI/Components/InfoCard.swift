//
//  InfoCard.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct InfoCard<Content: View>: View {
  let content: Content
  
  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }
  
  var body: some View {
    content
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.gray.opacity(0.1))
      .cornerRadius(16)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    InfoCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("What is Halo Fi?")
          .font(.headline)
          .foregroundColor(.gray)
        
        Text("Your voice-first financial assistant, designed to make understanding your finances simple, clear, and accessible.")
          .font(.body)
          .foregroundColor(.white)
          .multilineTextAlignment(.leading)
      }
    }
    .padding()
  }
}
