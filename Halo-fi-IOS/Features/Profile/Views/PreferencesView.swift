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
    /// "push_to_talk" or "hands_free". Phase 1 just persists the
    /// choice; ConversationCoordinator branches on it in Phase 2.
    @AppStorage("conversationMode") private var conversationMode = "push_to_talk"
    /// What Halo's own speech does while VoiceOver is running:
    /// duck (default) / mute / normal. Device-local — VoiceOver is a
    /// per-device setting — so it is not pushed to the backend.
    /// Read by StreamingAudioPlayer via VoiceOverPlaybackPolicy.
    @AppStorage(VoiceOverPlaybackPolicy.storageKey) private var voiceOverHaloBehavior = VoiceOverHaloBehavior.duck.rawValue

    @State private var isSaving = false
    @State private var showingResult = false
    @State private var resultMessage = ""
    @State private var resultSuccess = false
    /// Debounced auto-save handle. Each preference change schedules a
    /// save and cancels the previous one so rapid toggles produce a
    /// single API call after the user settles on a value.
    @State private var saveTask: Task<Void, Never>?

    // MARK: - Selection Options
    private let languageOptions: [SelectionOption] = [
        .init(id: "English", title: "English"),
        .init(id: "Spanish", title: "Spanish", disabledReason: "Coming Soon")
    ]

    private let themeModeOptions: [SelectionOption] = [
        .init(id: "System", title: "System"),
        .init(id: "Light", title: "Light"),
        .init(id: "Dark", title: "Dark"),
    ]

    private static let defaultVoiceId = "21m00Tcm4TlvDq8ikWAM"

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

    private let conversationModeOptions: [SelectionOption] = [
        .init(id: "push_to_talk", title: "Push to Talk"),
        .init(id: "hands_free", title: "Hands-Free (Beta)"),
    ]

    private let voiceOverBehaviorOptions: [SelectionOption] =
        VoiceOverHaloBehavior.allCases.map { .init(id: $0.rawValue, title: $0.title) }

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
        case "System":
            return systemColorScheme
        default:
            // Migrates older "High-Contrast" saves to System without
            // forcing the user to re-pick.
            return systemColorScheme
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

                // Conversation Style — Phase 2: backend selects the
                // ElevenLabs commit_strategy from this preference (manual
                // for PTT, VAD for hands-free), and ConversationCoordinator
                // already routes the mic loop accordingly. Default stays
                // Push to Talk for users who prefer explicit turns.
                PreferenceDropdownSection(
                    title: "Conversation Style",
                    subtitle: "Push to Talk: tap to speak, tap to send. Hands-Free: natural back-and-forth — Halo listens between replies.",
                    icon: "waveform",
                    options: conversationModeOptions,
                    selectedId: $conversationMode
                )

                // When VoiceOver is on — Halo's speech is the product for
                // many blind users, so it is never disabled silently. The
                // user picks: keep Halo quieter under VoiceOver (default),
                // mute Halo and read the transcript, or leave it alone.
                PreferenceDropdownSection(
                    title: "When VoiceOver is on",
                    subtitle: "Duck: Halo speaks more quietly so VoiceOver stays clear. Mute: Halo's voice is silent and VoiceOver reads the transcript. Normal: no change.",
                    icon: "ear",
                    options: voiceOverBehaviorOptions,
                    selectedId: $voiceOverHaloBehavior
                )

                Spacer(minLength: 100)
            }
            .padding(.top, 10)
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(selectedColorScheme)
        // Errors only — successful auto-saves are silent + haptic.
        // Showing "Saved" on every dropdown tap would be obnoxious.
        .alert("Couldn't save", isPresented: $showingResult) {
            Button("OK") { }
        } message: {
            Text(resultMessage)
        }
        .onAppear {
            let validIds = Set(voiceAgentOptions.map(\.id))
            if !validIds.contains(voiceAgent) {
                voiceAgent = Self.defaultVoiceId
            }
        }
        // Auto-save on any preference change. Each setter writes to
        // @AppStorage immediately for local persistence; we then
        // schedule a debounced backend push so a rapid toggle (e.g.
        // user opens dropdown, considers two options, settles) only
        // produces one API call.
        .onChange(of: voiceLanguage) { _, _ in scheduleAutoSave() }
        .onChange(of: themeMode) { _, _ in scheduleAutoSave() }
        .onChange(of: voiceAgent) { _, _ in scheduleAutoSave() }
        .onChange(of: voiceSpeed) { _, _ in scheduleAutoSave() }
        .onChange(of: conversationMode) { _, _ in scheduleAutoSave() }
        .onDisappear {
            // Cancel any pending debounced save when the user leaves
            // the screen — the @AppStorage write already happened, so
            // their local choice is preserved; we just don't need a
            // late API call firing after navigation.
            saveTask?.cancel()
        }
    }

    /// Debounced auto-save. Cancels any in-flight save and schedules
    /// a fresh one 350ms out. Tap-tap-tap on the same dropdown only
    /// produces one PUT.
    private func scheduleAutoSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await savePreferences(silent: true)
        }
    }

    private func savePreferences(silent: Bool = false) async {
        isSaving = true
        defer { isSaving = false }

        struct PrefsBody: Encodable {
            let voice_agent: String
            let voice_speed: Float
            let language: String
            let theme_mode: String
            let conversation_mode: String
        }

        struct PrefsResponse: Codable {
            let voice_agent: String?
            let voice_speed: Float?
            let language: String?
            let theme_mode: String?
            let conversation_mode: String?
        }

        do {
            let body = PrefsBody(
                voice_agent: voiceAgent,
                voice_speed: speedValue,
                language: voiceLanguage == "English" ? "en" : "es",
                theme_mode: themeMode.lowercased(),
                conversation_mode: conversationMode
            )
            let requestBody = try JSONEncoder().encode(body)

            let _: PrefsResponse = try await NetworkService.shared.authenticatedRequest(
                endpoint: APIEndpoints.Preferences.update,
                method: .PUT,
                body: requestBody,
                responseType: PrefsResponse.self
            )

            // Quiet confirmation that the choice persisted — no
            // interruptive alert. Routed through HapticEngine so it
            // gets the CoreHaptics treatment on supported devices.
            Haptics.engine.play(.tapLight)

            if !silent {
                resultSuccess = true
                resultMessage = "Your preferences have been saved."
                showingResult = true
            }
        } catch {
            // Even silent saves surface errors — the user needs to know
            // their setting didn't make it to the backend.
            resultSuccess = false
            resultMessage = "Unable to save preferences. Please try again."
            showingResult = true
        }
    }
}

#Preview {
    PreferencesView()
}
