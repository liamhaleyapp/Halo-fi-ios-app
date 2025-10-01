//
//  ModalHeader.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct ModalHeader: View {
  let title: String
  let onDone: () -> Void
  
  var body: some View {
    VStack(spacing: 0) {
      // Header with Done button
      HStack {
        Spacer()
        Button("Done") {
          onDone()
        }
        .foregroundColor(.white)
        .font(.body)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .padding(.top, 8)
      
      // Title
      Text(title)
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    ModalHeader(title: "Meet the Team", onDone: {})
  }
}
