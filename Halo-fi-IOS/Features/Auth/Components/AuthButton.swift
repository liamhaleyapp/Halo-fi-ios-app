//
//  AuthButton.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AuthButton: View {
  let title: String
  let isLoading: Bool
  let isEnabled: Bool
  let action: () -> Void
  
  var body: some View {
    Button(action: action) {
      HStack {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .scaleEffect(0.8)
        } else {
          Text(title)
            .font(.headline)
            .fontWeight(.semibold)
        }
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .background(
        LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .leading, endPoint: .trailing)
      )
      .cornerRadius(16)
    }
    .disabled(isLoading || !isEnabled)
    .opacity(isEnabled ? 1.0 : 0.6)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VStack(spacing: 20) {
      AuthButton(
        title: "Sign In",
        isLoading: false,
        isEnabled: true,
        action: {}
      )
      
      AuthButton(
        title: "Sign In",
        isLoading: true,
        isEnabled: false,
        action: {}
      )
    }
    .padding()
  }
}
