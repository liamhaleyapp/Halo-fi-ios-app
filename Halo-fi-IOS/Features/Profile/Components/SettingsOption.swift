//
//  SettingsOption.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SettingsOption: View {
  let icon: String
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 16) {
        Image(systemName: icon)
          .font(.title3)
          .foregroundColor(.blue)
          .frame(width: 28, height: 28)
          .accessibilityHidden(true)

        Text(title)
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(.primary)

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundColor(.gray)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(Color.gray.opacity(0.1))
      .cornerRadius(12)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityHint("Opens \(title)")
  }
}
