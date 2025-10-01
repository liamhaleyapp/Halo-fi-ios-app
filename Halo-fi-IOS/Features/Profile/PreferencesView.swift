//
//  PreferencesView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct PreferencesView: View {
  @Environment(\.dismiss) private var dismiss
  
  // MARK: - User Preferences
  @AppStorage("voiceLanguage") private var voiceLanguage = "English"
  @AppStorage("themeMode") private var themeMode = "Dark"
  @AppStorage("voiceAgent") private var voiceAgent = "Female"
  @AppStorage("voiceSpeed") private var voiceSpeed = "Normal"
  
  // MARK: - Dropdown States
  @State private var showingLanguageDropdown = false
  @State private var showingThemeDropdown = false
  @State private var showingVoiceAgentDropdown = false
  @State private var showingVoiceSpeedDropdown = false
  
  var body: some View {
    NavigationView {
      ZStack {
        // Background
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 16) {
          // Header
          HStack {
            Button(action: {
              dismiss()
            }) {
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
          
          // Content
          VStack(spacing: 16) {
            // Voice Assistant Language
            PreferenceDropdownSection(
              title: "Voice Assistant Language",
              subtitle: "Choose your preferred language for voice interactions",
              icon: "globe",
              selectedValue: voiceLanguage,
              isExpanded: $showingLanguageDropdown,
              options: ["English", "Spanish"]
            ) { newValue in
              voiceLanguage = newValue
              showingLanguageDropdown = false
            }
            
            // Theme Mode
            PreferenceDropdownSection(
              title: "Theme Mode",
              subtitle: "Select your preferred visual theme",
              icon: "paintbrush",
              selectedValue: themeMode,
              isExpanded: $showingThemeDropdown,
              options: ["Light", "Dark", "High-Contrast"]
            ) { newValue in
              themeMode = newValue
              showingThemeDropdown = false
            }
            
            // Voice Agent
            PreferenceDropdownSection(
              title: "Voice Agent",
              subtitle: "Choose your preferred voice assistant",
              icon: "person.wave.2",
              selectedValue: voiceAgent,
              isExpanded: $showingVoiceAgentDropdown,
              options: ["Male", "Female"]
            ) { newValue in
              voiceAgent = newValue
              showingVoiceAgentDropdown = false
            }
            
            // Voice Speed
            PreferenceDropdownSection(
              title: "Voice Speed",
              subtitle: "Adjust how fast the voice assistant speaks",
              icon: "speedometer",
              selectedValue: voiceSpeed,
              isExpanded: $showingVoiceSpeedDropdown,
              options: ["Slow", "Normal", "Fast"]
            ) { newValue in
              voiceSpeed = newValue
              showingVoiceSpeedDropdown = false
            }
            
            Spacer()
            
            // Save Button
            Button(action: savePreferences) {
              HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                  .font(.headline)
                  .foregroundColor(.white)
                
                Text("Save Preferences")
                  .font(.subheadline)
                  .fontWeight(.semibold)
                  .foregroundColor(.white)
              }
              .frame(maxWidth: .infinity)
              .frame(height: 48)
              .background(
                LinearGradient(
                  colors: [.blue, .purple],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              )
              .cornerRadius(12)
            }
            .accessibilityLabel("Save Preferences")
            .padding(.horizontal, 20)
            
            Spacer(minLength: 20)
          }
          .padding(.top, 5)
        }
      }
    }
    .navigationBarHidden(true)
  }
  
  private func savePreferences() {
    // TODO: Implement actual save logic
    // For now, just show success feedback
    
    // Haptic feedback
    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    impactFeedback.impactOccurred()
    
    // TODO: Show success toast or alert
  }
}

// MARK: - Preference Dropdown Section Component

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

// MARK: - Preference Option Button

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
  PreferencesView()
}
