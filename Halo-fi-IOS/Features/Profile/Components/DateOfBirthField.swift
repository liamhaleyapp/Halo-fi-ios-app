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
        .foregroundColor(.white)
      
      Button(action: onTap) {
        HStack {
          Text(dateFormatter.string(from: selectedDate))
            .foregroundColor(.white)
            .font(.body)
          
          Spacer()
          
          Image(systemName: "calendar")
            .foregroundColor(.gray)
            .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
      }
      .buttonStyle(PlainButtonStyle())
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    DateOfBirthField(selectedDate: Date()) {}
      .padding()
  }
}
