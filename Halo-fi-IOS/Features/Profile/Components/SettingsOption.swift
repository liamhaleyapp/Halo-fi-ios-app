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
      HStack(spacing: 20) {
        Image(systemName: icon)
          .font(.title2)
          .foregroundColor(.accentColor)
          .frame(width: 32, height: 32)
        
        Text(title)
          .font(.title3)
          .fontWeight(.medium)
          .foregroundColor(.primary)
        
        Spacer()
        
        Image(systemName: "chevron.right")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(Color(.tertiaryLabel))
      }
      .padding(.horizontal, 30)
      .padding(.vertical, 24)
      .background(Color(.secondarySystemBackground))
      .cornerRadius(16)
    }
  }
}
