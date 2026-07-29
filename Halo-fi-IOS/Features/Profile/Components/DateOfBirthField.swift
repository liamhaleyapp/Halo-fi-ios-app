//
//  DateOfBirthField.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct DateOfBirthField: View {
  let selectedDate: Date
  let onTap: () -> Void
  
  private var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Date of Birth")
        .font(.headline)
        .foregroundColor(.haloTextPrimary)

      Button(action: onTap) {
        HStack {
          Text(dateFormatter.string(from: selectedDate))
            .foregroundColor(.haloTextPrimary)
            .font(.body)

          Spacer()

          Image(systemName: "calendar")
            .foregroundColor(.haloTextSecondary)
            .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.haloSecondaryBackground)
        .cornerRadius(12)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(Color.haloSeparator, lineWidth: 1)
        )
      }
      .buttonStyle(HapticPlainButtonStyle())
    }
  }
}

#Preview {
  ZStack {
    Color.haloBackground.ignoresSafeArea()
    DateOfBirthField(selectedDate: Date()) {}
      .padding()
  }
}
