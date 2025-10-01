//
//  TermsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Terms View
struct TermsView: View {
  @Environment(\.dismiss) private var dismiss
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 0) {
        ModalHeader(title: "Terms of Service", onDone: { dismiss() })
        
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            Text("Last updated: December 2024")
              .font(.caption)
              .foregroundColor(.gray)
            
            Text("By using Halo Fi, you agree to these terms...")
              .font(.body)
              .foregroundColor(.white)
              .multilineTextAlignment(.leading)
              .lineLimit(nil)
            
            // Add more terms content here
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
  TermsView()
}
