//
//  PlaidLoadingView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct PlaidLoadingView: View {
  var body: some View {
    VStack(spacing: 20) {
      ProgressView()
        .scaleEffect(1.5)
        .progressViewStyle(CircularProgressViewStyle(tint: .white))
      
      Text("Setting up secure connection...")
        .font(.headline)
        .foregroundColor(.white)
      
      Text("This may take a few moments")
        .font(.subheadline)
        .foregroundColor(.white.opacity(0.7))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
  PlaidLoadingView()
}
