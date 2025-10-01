//
//  PreferenceDropdownSection.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct PreferenceDropdownSection: View {
  let title: String
  let subtitle: String
  let icon: String
  let selectedValue: String
  @Binding var isExpanded: Bool
  let options: [String]
  let onSelection: (String) -> Void
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.title3)
          .foregroundColor(.blue)
          .frame(width: 20, height: 20)
        
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(.white)
          
          Text(subtitle)
            .font(.caption)
            .foregroundColor(.gray)
            .lineLimit(2)
        }
        
        Spacer()
      }
      
      // Selected Value Button
      Button(action: {
        withAnimation(.easeInOut(duration: 0.2)) {
          isExpanded.toggle()
        }
      }) {
        HStack {
          Text(selectedValue)
            .font(.headline)
            .foregroundColor(.white)
            .fontWeight(.medium)
          
          Spacer()
          
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.title3)
            .foregroundColor(.blue)
            .rotationEffect(.degrees(isExpanded ? 0 : 0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(Color.gray.opacity(0.15))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
      }
      .accessibilityLabel("\(title): \(selectedValue)")
      .accessibilityHint("Tap to change \(title)")
      
      // Dropdown Options
      if isExpanded {
        VStack(spacing: 6) {
          ForEach(options, id: \.self) { option in
            PreferenceOptionButton(
              option: option,
              selectedValue: selectedValue,
              onSelection: onSelection
            )
          }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 16)
    .background(Color.gray.opacity(0.08))
    .cornerRadius(16)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    PreferenceDropdownSection(
      title: "Voice Language",
      subtitle: "Choose your preferred language",
      icon: "globe",
      selectedValue: "English",
      isExpanded: .constant(true),
      options: ["English", "Spanish", "French"]
    ) { _ in }
    .padding()
  }
}
