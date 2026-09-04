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
    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    headerRow
                    TranscriptView(
                        entries: viewModel.entries,
                        onCopyEntry: viewModel.copyEntry,
                        isProcessing: viewModel.state == .processing
                    )
                    QuickActionStack(
                        chips: QuickActionChip.v1.filter { $0.id != "log-expense" || userManager.capabilities.showsBenefitsLane },
                        collapsible: !viewModel.entries.isEmpty
                    ) { chip in send(chip.prompt) }
                    TextInputArea(
                        text: $viewModel.textInput,
                        state: viewModel.state,
                        isEnabled: true,
                        onSend: { send(viewModel.textInput) },
                        onSwitchToVoice: { openVoice(prompt: nil) },
                        onStopSpeaking: { viewModel.coordinator.stopSpeaking() },
                        autoFocus: false
                    )
                }
                .readableContentWidth()

                micButton
                    .padding(.trailing, 20)
                    .padding(.bottom, viewModel.entries.isEmpty ? 300 : 148)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showingVoice, onDismiss: {
                voicePrompt = nil
                NotificationCenter.default.post(name: .conversationDismissed, object: nil)
            }) {
                ConversationView(initialPrompt: voicePrompt)
            }
            .confirmationDialog("Clear this conversation?", isPresented: $showingClearConfirm, titleVisibility: .visible) {
                Button("Clear conversation", role: .destructive) {
                    viewModel.store.reset()
                    UIAccessibility.post(notification: .announcement, argument: "Conversation cleared.")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the thread from this phone. Halo's memory of your accounts is not affected.")
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
                ? "Type below, pick a quick action, or tap the microphone to talk."
                : "\(VoiceOverFormatter.count(viewModel.entries.count, singular: "message", plural: "messages")) in this thread. Type below or tap the microphone."
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ScreenReaderSummaryHeader(verdict: "Halo", detail: headerDetail, tone: .neutral)
            Menu {
                Button(role: .destructive) { showingClearConfirm = true } label: {
                    Label("Clear conversation", systemImage: "trash")
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

    private var micButton: some View {
        Button { openVoice(prompt: nil) } label: {
            Image(systemName: "mic.fill")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(HapticPlainButtonStyle())
        .accessibilityLabel("Talk to Halo")
        .accessibilityHint("Opens the voice conversation. Hands-free by default; the big button mutes your microphone.")
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
