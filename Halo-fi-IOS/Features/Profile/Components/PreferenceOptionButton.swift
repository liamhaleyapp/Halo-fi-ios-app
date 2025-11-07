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
  let isDisabled: Bool
  let onSelection: (String) -> Void
  
  private var isSelected: Bool {
    option == selectedValue
  }
  
  private var backgroundColor: Color {
    if isDisabled {
      return Color.gray.opacity(0.05)
    }
    return isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1)
  }
  
  private var strokeColor: Color {
    if isDisabled {
      return Color.clear
    }
    return isSelected ? Color.blue : Color.clear
  }

  private var displayText: String {
    isDisabled ? "\(option) (Coming Soon)" : option
  }
  
  var body: some View {
    Button(action: {
      guard !isDisabled else { return }
      onSelection(option)
    }) {
      HStack {
        Text(displayText)
          .font(.subheadline)
          .foregroundColor(isDisabled ? .gray.opacity(0.6) : (isSelected ? .white : .gray))
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
    .accessibilityLabel("\(displayText) option")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityHint(isDisabled ? "Coming soon" : (isSelected ? "Currently selected" : "Tap to select"))
    .disabled(isDisabled)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VStack(spacing: 8) {
      PreferenceOptionButton(
        option: "English",
        selectedValue: "English",
        isDisabled: false,
        onSelection: { _ in }
      )
      
      PreferenceOptionButton(
        option: "Spanish",
        selectedValue: "English",
        isDisabled: true,
        onSelection: { _ in }
      )
    }
    .padding()
  }
}
