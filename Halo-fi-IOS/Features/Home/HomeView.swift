//
//  HomeView.swift
//  Halo-fi-IOS
//
//  WP7 — the Agent tab is a text-first chat thread: transcript + composer
//  + quick-action chips, with a floating mic button that opens the voice
//  modal (ConversationView). Voice and text share one session and one
//  transcript (ConversationTranscriptStore.shared), which persists across
//  launches. Typed messages get text-only replies; VoiceOver reads them.
//

import SwiftUI

struct HomeView: View {
    @Environment(UserManager.self) private var userManager

    @State private var viewModel = ConversationViewModel()
    @State private var showingVoice = false
    @State private var voicePrompt: String? = nil
    @State private var showingShortcuts = false
    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow
                TranscriptView(
                    entries: viewModel.entries,
                    onCopyEntry: viewModel.copyEntry,
                    isProcessing: viewModel.state == .processing
                )
                ShortcutsButton { showingShortcuts = true }
                TextInputArea(
                    text: $viewModel.textInput,
                    state: viewModel.state,
                    isEnabled: true,
                    onSend: { send(viewModel.textInput) },
                    onSwitchToVoice: { openVoice(prompt: nil) },
                    onStopSpeaking: { viewModel.coordinator.stopSpeaking() },
                    autoFocus: false,
                    prominentVoice: true
                )
            }
            .readableContentWidth()
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showingVoice, onDismiss: {
                voicePrompt = nil
                NotificationCenter.default.post(name: .conversationDismissed, object: nil)
            }) {
                ConversationView(initialPrompt: voicePrompt)
            }
            .sheet(isPresented: $showingShortcuts) {
                ShortcutsSheet(chips: QuickActionChip.available(benefitsLane: userManager.capabilities.showsBenefitsLane)) { chip in
                    send(chip.prompt)
                }
            }
            .sheet(isPresented: $showingHistory) {
                PreviousConversationsView(store: viewModel.store) {
                    UIAccessibility.post(notification: .announcement, argument: "Conversation loaded. Keep going below.")
                }
            }
            // Phase 12 — cross-tab quick actions. A prompt is sent as text;
            // no prompt means the user asked for the microphone.
            .onReceive(NotificationCenter.default.publisher(for: .askHaloRequested)) { notification in
                let prompt = (notification.userInfo?["prompt"] as? String) ?? ""
                if prompt.isEmpty { openVoice(prompt: nil) } else { send(prompt) }
            }
            .onAppear {
                ConversationTranscriptStore.shared.bind(userId: userManager.currentUser.map { "\($0.id)" })
            }
            // Read Halo's reply aloud through VoiceOver when it lands in
            // the thread (the voice modal covers this with TTS itself).
            .onChange(of: viewModel.entries) { old, new in
                // Never announce while ANY voice session is on screen (the
                // Budget and Benefits tabs open the modal too): VoiceOver's
                // voice would go straight into the hot mic.
                guard !showingVoice, !viewModel.coordinator.isVoiceModalPresented,
                      UIAccessibility.isVoiceOverRunning,
                      let last = new.last, last.speaker == .agent, !last.isStreaming else { return }
                let wasFinished = old.last?.id == last.id && old.last?.isStreaming == false
                if !wasFinished {
                    UIAccessibility.post(notification: .announcement, argument: "Halo said: \(last.text)")
                }
            }
        }
    }

    // MARK: - Pieces

    private var headerDetail: String {
        switch viewModel.state {
        case .processing: return "Halo is thinking."
        case .speaking: return "Halo is speaking."
        case .connecting: return "Connecting."
        default:
            return viewModel.entries.isEmpty
                ? "Type below, open Shortcuts, or tap the microphone to talk."
                : "\(VoiceOverFormatter.count(viewModel.entries.count, singular: "message", plural: "messages")) in this conversation. Type below or tap the microphone."
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ScreenReaderSummaryHeader(verdict: "Halo", detail: headerDetail, tone: .neutral)
            Menu {
                Button { showingHistory = true } label: {
                    Label("Previous conversations", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    viewModel.store.startNewSession()
                    UIAccessibility.post(notification: .announcement, argument: "New conversation. The last one is saved under Previous conversations.")
                } label: {
                    Label("New conversation", systemImage: "plus.bubble")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Conversation options")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }


    // MARK: - Actions

    private func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        viewModel.textInput = ""
        Task {
            if !viewModel.coordinator.isConnected {
                await viewModel.connectForText()
            }
            await viewModel.coordinator.sendText(message, spoken: false)
        }
    }

    private func openVoice(prompt: String?) {
        voicePrompt = prompt
        showingVoice = true
    }
}

#Preview {
    HomeView()
}
