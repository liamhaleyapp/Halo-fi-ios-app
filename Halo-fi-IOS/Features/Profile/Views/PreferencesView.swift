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

    // MARK: - Selection Options
    private let languageOptions: [SelectionOption] = [
        .init(id: "English", title: "English"),
        .init(id: "Spanish", title: "Spanish", disabledReason: "Coming Soon")
    ]

    private let themeModeOptions: [SelectionOption] = [
        .init(id: "System", title: "System"),
        .init(id: "Light", title: "Light"),
        .init(id: "Dark", title: "Dark"),
        .init(id: "High-Contrast", title: "High-Contrast")
    ]

    private let voiceAgentOptions: [SelectionOption] = [
        .init(id: "Male", title: "Male"),
        .init(id: "Female", title: "Female")
    ]

    private let voiceSpeedOptions: [SelectionOption] = [
        .init(id: "Slow", title: "Slow"),
        .init(id: "Normal", title: "Normal"),
        .init(id: "Fast", title: "Fast")
    ]

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
        ScrollView {
            VStack(spacing: 16) {
                // Voice Assistant Language
                PreferenceDropdownSection(
                    title: "Voice Assistant Language",
                    subtitle: "Choose your preferred language for voice interactions",
                    icon: "globe",
                    options: languageOptions,
                    selectedId: $voiceLanguage
                )

                // Theme Mode
                PreferenceDropdownSection(
                    title: "Theme Mode",
                    subtitle: "Select your preferred visual theme",
                    icon: "paintbrush",
                    options: themeModeOptions,
                    selectedId: $themeMode
                )

                // Voice Agent
                PreferenceDropdownSection(
                    title: "Voice Agent",
                    subtitle: "Choose your preferred voice assistant",
                    icon: "person.wave.2",
                    options: voiceAgentOptions,
                    selectedId: $voiceAgent
                )

                // Voice Speed
                PreferenceDropdownSection(
                    title: "Voice Speed",
                    subtitle: "Adjust how fast the voice assistant speaks",
                    icon: "speedometer",
                    options: voiceSpeedOptions,
                    selectedId: $voiceSpeed
                )

                Spacer(minLength: 40)

                // Save Button
                SavePreferencesButton(onSave: savePreferences)

                Spacer(minLength: 100)
            }
            .padding(.top, 10)
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.large)
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
