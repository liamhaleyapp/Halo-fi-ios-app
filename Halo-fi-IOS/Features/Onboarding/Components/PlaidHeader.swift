//
//  PlaidHeader.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct PlaidHeader: View {
  let onCancel: () -> Void
  
  var body: some View {
    VStack(spacing: 16) {
      HStack {
        Button("Cancel") {
          onCancel()
        }
        .foregroundColor(.white)
        
        Spacer()
        
        Text("Connect Your Bank")
          .font(.headline)
          .foregroundColor(.white)
        
        Spacer()
        
        // Invisible button for balance
        Button("") { }
          .opacity(0)
      }
      .padding(.horizontal)
      
      Text("Securely connect your accounts to get personalized financial insights")
        .font(.subheadline)
        .foregroundColor(.white.opacity(0.8))
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .padding(.top)
    .background(
      LinearGradient(
        colors: [Color.indigo, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    PlaidHeader(onCancel: {})
  }
}
