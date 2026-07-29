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
      HStack {
        Spacer()
        Button("Done") {
          onDone()
        }
        .foregroundColor(.haloTextPrimary)
        .font(.body)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityHint("Closes this screen")
      }
      .padding(.top, 8)
      
      Text(title)
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(.haloTextPrimary)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .accessibilityAddTraits(.isHeader)
    }
  }
}

#Preview {
  ZStack {
    Color.haloBackground.ignoresSafeArea()
    ModalHeader(title: "Meet the Team", onDone: {})
  }
}
