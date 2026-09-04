//
//  AccessibilitySettingsView.swift
//  Halo-fi-IOS
//
//  Settings → Accessibility (WP4): haptic intensity, speech verbosity, and
//  what Halo's voice does under VoiceOver (the WP1 ducking preference,
//  same key as Preferences). All device-local.
//

import SwiftUI

struct AccessibilitySettingsView: View {
    @AppStorage(AccessibilityPrefs.hapticIntensityKey) private var hapticIntensity: Double = 1.0
    @AppStorage(AccessibilityPrefs.speechVerbosityKey) private var speechVerbosity: String = "standard"
    @AppStorage(VoiceOverPlaybackPolicy.storageKey) private var voiceOverHaloBehavior = VoiceOverHaloBehavior.duck.rawValue

    private let intensityOptions: [(Double, String)] = [(0, "Off"), (0.5, "Light"), (1.0, "Normal"), (1.4, "Strong")]

    var body: some View {
        Form {
            Section {
                Picker("Haptic intensity", selection: $hapticIntensity) {
                    ForEach(intensityOptions, id: \.0) { value, title in
                        Text(title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("How strong the taps and ticks feel. Off disables them.")
                .onChange(of: hapticIntensity) { _, _ in
                    Haptics.engine.play(.tapCrisp)
                }
            } header: {
                Text("Haptics")
            } footer: {
                Text("Every state change has a word, a pill and a haptic — never colour alone. This controls the haptic.")
            }

            Section {
                Picker("Speech", selection: $speechVerbosity) {
                    Text("Brief").tag("brief")
                    Text("Standard").tag("standard")
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Brief keeps screen summaries to one sentence.")
            } header: {
                Text("Speech verbosity")
            } footer: {
                Text("Brief: the summary Halo speaks when a screen opens is one sentence. Standard: up to three.")
            }

            Section {
                Picker("When VoiceOver is on", selection: $voiceOverHaloBehavior) {
                    ForEach(VoiceOverHaloBehavior.allCases, id: \.rawValue) { behavior in
                        Text(behavior.title).tag(behavior.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("When VoiceOver is on")
            } footer: {
                Text("Duck: Halo speaks more quietly so VoiceOver stays clear. Mute: Halo's voice is silent and VoiceOver reads the transcript. Normal: no change.")
            }
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.large)
    }
}
