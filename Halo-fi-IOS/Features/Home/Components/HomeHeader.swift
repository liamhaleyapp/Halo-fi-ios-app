//
//  HomeHeader.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct HomeHeader: View {
  let userName: String
  
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Hello, \(userName)")
        .font(.largeTitle)
        .fontWeight(.bold)
        .foregroundColor(.white)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.top, 65)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    HomeHeader(userName: "Christopher")
  }
}
