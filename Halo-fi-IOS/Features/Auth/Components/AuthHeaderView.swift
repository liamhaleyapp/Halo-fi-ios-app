//
//  AuthHeaderView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AuthHeaderView: View {
  let title: String
  let subtitle: String
  let onBackTap: () -> Void
  
  var body: some View {
    VStack(spacing: 16) {
      // Back Arrow
      HStack {
        Button(action: onBackTap) {
          Image(systemName: "chevron.left")
            .font(.title2)
            .foregroundColor(.white)
            .padding(8)
            .background(Color.white.opacity(0.2))
            .clipShape(Circle())
        }
        .accessibilityLabel("Back")
        .accessibilityHint("Tap to go back")
        
        Spacer()
      }
      .padding(.horizontal, 20)
      
      // App Logo
      HaloFiLogo(size: 80)
      
      Text(title)
        .font(.largeTitle)
        .fontWeight(.bold)
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(2)
      
      Text(subtitle)
        .font(.body)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
        .accessibilitySortPriority(1)
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    AuthHeaderView(
      title: "Welcome Back",
      subtitle: "Sign in to continue your financial journey",
      onBackTap: {}
    )
    .padding(.top, 40)
  }
}
