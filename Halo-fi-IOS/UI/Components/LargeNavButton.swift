//
//  LargeNavButton.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct LargeNavButton: View {
  let title: String
  let icon: String
  let tileColor: Color
  
  var body: some View {
    HStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 12)
          .fill(tileColor)
          .frame(width: 72, height: 72)
        
        Image(systemName: icon)
          .font(.title2)
          .foregroundColor(.white)  // on the colored tile — stays white in both modes
          .accessibilityHidden(true)
      }

      Text(title)
        .font(.title3)
        .fontWeight(.semibold)
        .foregroundColor(.haloTextPrimary)
        .multilineTextAlignment(.leading)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)

      Spacer()

      Image(systemName: "chevron.right")
        .font(.headline)
        .foregroundColor(.haloTextSecondary)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(Color.haloSecondaryBackground)
    .cornerRadius(16)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityHint("Opens \(title)")
  }
}

#Preview {
  ZStack { Color.haloBackground.ignoresSafeArea() }
    .overlay(
      LargeNavButton(
        title: "Preview Button",
        icon: "creditcard.fill",
        tileColor: .blue
      )
      .padding()
    )
}
