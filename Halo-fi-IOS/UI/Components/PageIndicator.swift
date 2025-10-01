//
//  PageIndicator.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct PageIndicator: View {
  let currentPage: Int
  let totalPages: Int
  
  var body: some View {
    HStack(spacing: 8) {
      ForEach(0..<totalPages, id: \.self) { index in
        Circle()
          .fill(currentPage == index ? Color.white : Color.gray.opacity(0.5))
          .frame(width: 8, height: 8)
          .animation(.easeInOut, value: currentPage)
      }
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VStack {
      Spacer()
      PageIndicator(currentPage: 1, totalPages: 3)
      Spacer()
    }
  }
}
