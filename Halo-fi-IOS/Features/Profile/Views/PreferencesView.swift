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
    @AppStorage("voiceAgent") private var voiceAgent = "21m00Tcm4TlvDq8ikWAM"
    @AppStorage("voiceSpeed") private var voiceSpeed = "Normal"

    @State private var isSaving = false
    @State private var showingResult = false
    @State private var resultMessage = ""
    @State private var resultSuccess = false

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
        .init(id: "21m00Tcm4TlvDq8ikWAM", title: "Rachel (Female, Calm)"),
        .init(id: "pNInz6obpgDQGcFmaJgB", title: "Adam (Male, Deep)"),
        .init(id: "9BWtsMINqrJLrRacOk9x", title: "Aria (Female, Warm)"),
        .init(id: "IKne3meq5aSn9XLyUdCD", title: "Charlie (Male, Natural)"),
    ]

    private let voiceSpeedOptions: [SelectionOption] = [
        .init(id: "Slow", title: "Slow"),
        .init(id: "Normal", title: "Normal"),
        .init(id: "Fast", title: "Fast")
    ]

    private var speedValue: Float {
        switch voiceSpeed {
        case "Slow": return 0.8
        case "Fast": return 1.3
        default: return 1.0
        }
    }

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
                    title: "Voice Assistant",
                    subtitle: "Choose your preferred voice",
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
                SavePreferencesButton(onSave: {
                    Task { await savePreferences() }
                })
                .disabled(isSaving)

                Spacer(minLength: 100)
            }
            .padding(.top, 10)
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(selectedColorScheme)
        .alert(resultSuccess ? "Saved" : "Error", isPresented: $showingResult) {
            Button("OK") { }
        } message: {
            Text(resultMessage)
        }
    }

    private func savePreferences() async {
        isSaving = true
        defer { isSaving = false }

        struct PrefsBody: Encodable {
            let voice_agent: String
            let voice_speed: Float
            let language: String
            let theme_mode: String
        }

        struct PrefsResponse: Codable {
            let voice_agent: String?
            let voice_speed: Float?
            let language: String?
            let theme_mode: String?
        }

        do {
            let body = PrefsBody(
                voice_agent: voiceAgent,
                voice_speed: speedValue,
                language: voiceLanguage == "English" ? "en" : "es",
                theme_mode: themeMode.lowercased()
            )
            let requestBody = try JSONEncoder().encode(body)

            let _: PrefsResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: APIEndpoints.Preferences.update,
                method: .PUT,
                body: requestBody,
                responseType: PrefsResponse.self
            )

            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            resultSuccess = true
            resultMessage = "Your preferences have been saved."
        } catch {
            resultSuccess = false
            resultMessage = "Unable to save preferences. Please try again."
        }
        showingResult = true
    }
}

#Preview {
    PreferencesView()
}
