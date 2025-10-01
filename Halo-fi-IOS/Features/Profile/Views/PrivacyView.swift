//
//  PrivacyView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Privacy View
struct PrivacyView: View {
  @Environment(\.dismiss) private var dismiss
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 0) {
        ModalHeader(title: "Privacy Policy", onDone: { dismiss() })
        
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            Text("Last updated: December 2024")
              .font(.caption)
              .foregroundColor(.gray)
            
            Text("Your privacy is important to us. This policy describes how we collect, use, and protect your information...")
              .font(.body)
              .foregroundColor(.white)
              .multilineTextAlignment(.leading)
              .lineLimit(nil)
            
            // Add more privacy content here
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 100)
        }
        
        Spacer()
      }
    }
  }
}

// MARK: - Preview
#Preview {
  PrivacyView()
}
