//
//  PermissionBenefitRow.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/18/25.
//

import SwiftUI

struct PermissionBenefitRow: View {
  let icon: String
  let title: String
  let description: String
  
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.blue)
        .frame(width: 30)
        .accessibilityHidden(true)
      
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      
      Spacer()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title). \(description)")
  }
}
