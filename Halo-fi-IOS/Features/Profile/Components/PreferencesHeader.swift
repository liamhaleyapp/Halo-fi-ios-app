//
//  PreferencesHeader.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct PreferencesHeader: View {
  let onBack: () -> Void
  
  var body: some View {
    HStack {
      Button(action: onBack) {
        Image(systemName: "chevron.left")
          .font(.title2)
          .foregroundColor(.white)
          .frame(width: 40, height: 40)
          .background(Color.gray.opacity(0.2))
          .clipShape(Circle())
      }
      
      Spacer()
      
      Text("Preferences")
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(.white)
      
      Spacer()
      
      // Placeholder for balance
      Color.clear
        .frame(width: 40, height: 40)
    }
    .padding(.horizontal, 20)
    .padding(.top, 15)
    .padding(.bottom, 20)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    PreferencesHeader(onBack: {})
  }
}
