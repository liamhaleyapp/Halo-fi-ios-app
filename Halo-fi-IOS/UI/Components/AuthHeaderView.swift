//
//  AuthHeaderView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Auth Header Component
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
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // App Logo/Icon
            Circle()
                .fill(LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                )
            
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(subtitle)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Preview
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
