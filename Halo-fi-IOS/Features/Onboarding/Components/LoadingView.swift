//
//  qwerty.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/1/25.
//

import SwiftUI

struct LoadingView: View {
  
  var body: some View {
    VStack(spacing: 20) {
      ProgressView()
        .scaleEffect(1.5)
        .tint(.accentColor)
      
      VStack(spacing: 8) {
        Text("Setting up secure connection...")
          .font(.headline)
          .foregroundColor(.primary)
        
        Text("This may take a few moments")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
  }
}
