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
  @AppStorage("themeMode") private var themeMode = "System"
  @AppStorage("voiceAgent") private var voiceAgent = "Female"
  @AppStorage("voiceSpeed") private var voiceSpeed = "Normal"
  
  // MARK: - Dropdown States
  @State private var showingLanguageDropdown = false
  @State private var showingThemeDropdown = false
  @State private var showingVoiceAgentDropdown = false
  @State private var showingVoiceSpeedDropdown = false
  
  private var systemColorScheme: ColorScheme? {
    switch UIScreen.main.traitCollection.userInterfaceStyle {
    case .light:
      return .light
    case .dark:
      return .dark
    default:
      return nil
    }
  }
  
  private var selectedColorScheme: ColorScheme? {
    switch themeMode {
    case "Light":
      return .light
    case "Dark":
      return .dark
    case "High-Contrast":
      return .dark
    case "System":
      return systemColorScheme
    default:
      return nil
    }
  }
  
  var body: some View {
    NavigationView {
      ZStack {
        // Background
        Color(.systemBackground).ignoresSafeArea()
        
        VStack(spacing: 16) {
          // Header
          PreferencesHeader(onBack: { dismiss() })
          
          // Content
          VStack(spacing: 16) {
            // Voice Assistant Language
            PreferenceDropdownSection(
              title: "Voice Assistant Language",
              subtitle: "Choose your preferred language for voice interactions",
              icon: "globe",
              selectedValue: voiceLanguage,
              isExpanded: $showingLanguageDropdown,
              options: ["English", "Spanish"],
              disabledOptions: ["Spanish"]
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
              options: ["System", "Light", "Dark", "High-Contrast"]
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
            SavePreferencesButton(onSave: savePreferences)
            
            Spacer(minLength: 20)
          }
          .padding(.top, 5)
        }
      }
    }
    .navigationBarHidden(true)
    .preferredColorScheme(selectedColorScheme)
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

#Preview {
  PreferencesView()
}
