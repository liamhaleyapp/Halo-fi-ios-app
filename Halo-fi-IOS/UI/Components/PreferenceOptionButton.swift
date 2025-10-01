//
//  PreferenceOptionButton.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct PreferenceOptionButton: View {
  let option: String
  let selectedValue: String
  let onSelection: (String) -> Void
  
  private var isSelected: Bool {
    option == selectedValue
  }
  
  private var backgroundColor: Color {
    isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1)
  }
  
  private var strokeColor: Color {
    isSelected ? Color.blue : Color.clear
  }
  
  var body: some View {
    Button(action: {
      onSelection(option)
    }) {
      HStack {
        Text(option)
          .font(.subheadline)
          .foregroundColor(isSelected ? .white : .gray)
          .fontWeight(isSelected ? .semibold : .medium)
        
        Spacer()
        
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.caption)
            .foregroundColor(.blue)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(backgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(strokeColor, lineWidth: 1)
      )
    }
    .accessibilityLabel("\(option) option")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityHint(isSelected ? "Currently selected" : "Tap to select")
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VStack(spacing: 8) {
      PreferenceOptionButton(
        option: "English",
        selectedValue: "English",
        onSelection: { _ in }
      )
      
      PreferenceOptionButton(
        option: "Spanish",
        selectedValue: "English",
        onSelection: { _ in }
      )
    }
    .padding()
  }
}
