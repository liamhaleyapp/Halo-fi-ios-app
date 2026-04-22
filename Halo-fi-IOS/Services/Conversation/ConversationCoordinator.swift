//
//  ConversationCoordinator.swift
//  Halo-fi-IOS
//
//  THE authority for conversation state. Owns:
//  - Session ID
//  - Connection lifecycle
//  - Event stream
//  - Audio session transitions
//  - Mutual exclusion (recording OR speaking OR typing)
//
//  UI calls only public methods; internal services (VoiceService, AgentWebSocketManager) are private.
//

import AVFoundation
import Foundation
import UIKit

@Observable
@MainActor
final class ConversationCoordinator {
    // MARK: - Singleton

    static let shared = ConversationCoordinator()

    // MARK: - Public State (Read-Only)

    private(set) var state: ConversationState = .idle
    private(set) var sessionId: String?
    private(set) var isMuted: Bool = false
    private(set) var isPrivacyMode: Bool = false
    private(set) var interactionMode: InteractionMode = .voice

    // MARK: - Event Stream

    /// Store subscribes to this to receive events
    var onEvent: ((ConversationEvent) -> Void)?

    // MARK: - Private Services

    private let voiceService: VoiceService
    private let agentWebSocket: AgentWebSocketManager
    private var streamingAudioPlayer: StreamingAudioPlayer?
    private var audioFeedback: AudioFeedbackService = AudioFeedbackService()
    private let sttService: ElevenLabsSTTService

    /// Speaks supervisor voice_status via on-device TTS so the user hears
    /// feedback within ~500ms of sending a message, instead of ~3s of
    /// silence while the agent graph runs. Stopped as soon as the first
    /// audio_chunk arrives so it can't overlap with agent TTS.
    private let voiceStatusSynthesizer = AVSpeechSynthesizer()

    // MARK: - Transcript Store (for draft management)

    private var transcriptStore: ConversationTranscriptStore?

    // MARK: - Private State

    private var currentAgentResponseId: UUID?
    private var pendingRetryMessage: String?
    private var isVoiceSessionActive = false
    private var agentEventTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        self.voiceService = VoiceService.shared
        self.agentWebSocket = AgentWebSocketManager.shared
        self.sttService = ElevenLabsSTTService()

        setupNotifications()
        setupSTTCallbacks()
    }

    // MARK: - Dependency Injection (for services created after init)

    func configure(
        streamingAudioPlayer: StreamingAudioPlayer,
        audioFeedback: AudioFeedbackService,
        transcriptStore: ConversationTranscriptStore
    ) {
        self.streamingAudioPlayer = streamingAudioPlayer
        self.audioFeedback = audioFeedback
        self.transcriptStore = transcriptStore

        streamingAudioPlayer.onPlaybackFinished = { [weak self] in
            Task { @MainActor in
                self?.handleSpeakingFinished()
            }
        }
    }

    // MARK: - Public API

    /// Connect to the backend
    func connect() async {
        guard state == .idle || state == .disconnected else { return }

        setState(.connecting)
        sessionId = UUID().uuidString

        do {
            try await agentWebSocket.connect()

            // Start consuming events from the new stream
            agentEventTask?.cancel()
            agentEventTask = Task { [weak self] in
                guard let self else { return }
                for await event in self.agentWebSocket.events {
                    self.handleAgentEvent(event)
                }
            }

            // Pre-warm capture pipeline so the user's first tap has no
            // engine-spin-up / tap-install latency. Best-effort — we
            // swallow errors because the view should still appear even
            // if mic permission hasn't been granted yet.
            prewarmTask?.cancel()
            prewarmTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.voiceService.preWarmCapture()
                } catch {
                    Logger.debug("ConversationCoordinator: Pre-warm skipped: \(error)")
                }
            }
        } catch {
            setState(.error(error.localizedDescription))
        }
    }

    /// Disconnect from the backend
    func disconnect() {
        agentEventTask?.cancel()
        agentEventTask = nil
        prewarmTask?.cancel()
        prewarmTask = nil

        voiceService.stopRecording()
        voiceService.teardownCapture()
        sttService.disconnect()
        agentWebSocket.disconnect()
        streamingAudioPlayer?.stop()
        transcriptStore?.discardDraft()

        isVoiceSessionActive = false
        sessionId = nil
        setState(.idle)
    }

    /// Set interaction mode (voice vs text)
    func setInteractionMode(_ mode: InteractionMode) {
        guard mode != interactionMode else { return }

        // If switching away from voice while listening, stop
        if interactionMode == .voice && state == .listening {
            stopListening()
        }

        interactionMode = mode

        // Play tab switch feedback (sound + haptic)
        audioFeedback.playTabSwitchFeedback()
    }

    /// Start listening (voice mode)
    func startListening() async {
        guard state == .idle || state == .speaking else { return }
        guard interactionMode == .voice else { return }

        // Don't start mic if audio is buffering or playing — stop it and return
        if streamingAudioPlayer?.isPlaying == true || streamingAudioPlayer?.isBuffering == true {
            streamingAudioPlayer?.stop()
            setState(.idle)
            return
        }

        // Check permission
        let permissionManager = PermissionManager.shared
        let status = await permissionManager.requestMicrophonePermission()

        guard status == .granted else {
            setState(.permissionNeeded)
            return
        }

        // Show connecting state while establishing STT connection
        setState(.connecting)

        do {
            // Set up callback to start recording when session is ready
            sttService.onSessionReady = { [weak self] in
                guard let self = self else { return }
                Task { @MainActor in
                    do {
                        // Wire audio buffers from VoiceService to STT service
                        self.voiceService.onAudioBuffer = { [weak self] buffer in
                            guard let self = self else { return }
                            Task {
                                await self.sttService.sendAudioBuffer(buffer)
                            }
                        }

                        // Start recording first, then signal the user
                        try await self.voiceService.startRecording()
                        self.setState(.listening)
                        self.audioFeedback.feedbackForStateChange(.listening)
                        self.isVoiceSessionActive = true
                    } catch {
                        self.handleVoiceSetupError(error)
                    }
                }
            }

            // Connect to ElevenLabs STT (fetches fresh token each time)
            try await sttService.connect()

        } catch {
            handleVoiceSetupError(error)
        }
    }

    private func handleVoiceSetupError(_ error: Error) {
        // Clean up on failure
        sttService.onSessionReady = nil
        sttService.disconnect()
        voiceService.onAudioBuffer = nil
        isVoiceSessionActive = false

        setState(.error(error.localizedDescription))
    }

    /// Stop listening (voice mode) - finalize and send transcript
    func stopListening() {
        guard state == .listening else { return }

        // Play stop listening feedback immediately
        audioFeedback.feedbackForStateChange(.idle)

        // Mark session inactive BEFORE disconnect to prevent "unexpected disconnect" warning
        isVoiceSessionActive = false

        // Stop recording and STT
        voiceService.stopRecording()
        voiceService.onAudioBuffer = nil
        sttService.disconnect()

        // Finalize draft and send to agent
        if let finalText = transcriptStore?.finalizeDraft(), !finalText.trimmingCharacters(in: .whitespaces).isEmpty {
            setState(.processing)

            Task {
                await sendTextInternal(finalText)
            }
        } else {
            // Empty or no transcript - just go idle
            setState(.idle)
        }
    }

    /// Internal: Stop listening after committed transcript (VAD auto-stop)
    private func stopListeningAndProcess() {
        guard state == .listening else { return }

        // Play stop listening feedback immediately
        audioFeedback.feedbackForStateChange(.idle)

        // Mark session inactive BEFORE disconnect to prevent "unexpected disconnect" warning
        isVoiceSessionActive = false

        // Stop recording and STT
        voiceService.stopRecording()
        voiceService.onAudioBuffer = nil
        sttService.disconnect()

        // Finalize draft and send to agent
        if let finalText = transcriptStore?.finalizeDraft() {
            setState(.processing)

            Task {
                await sendTextInternal(finalText)
            }
        } else {
            // Empty or invalid transcript - just go idle
            setState(.idle)
        }
    }

    /// Send a text message (from text input)
    func sendText(_ message: String) async {
        guard !message.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard state == .idle || state == .listening else { return }

        // Stop listening if active (without discarding - stopListening handles that)
        if state == .listening {
            voiceService.stopRecording()
            voiceService.onAudioBuffer = nil
            sttService.disconnect()
            isVoiceSessionActive = false
            transcriptStore?.discardDraft()
        }

        // Emit user message event (for text input, need to show in UI)
        emitEvent(.userText(message))

        // Send to agent
        setState(.processing)
        await sendTextInternal(message)
    }

    /// Internal: Send text to agent (used by both text input and voice finalization)
    private func sendTextInternal(_ message: String) async {
        do {
            currentAgentResponseId = UUID()

            let context: [String: AnyCodable] = [
                "platform": AnyCodable("ios"),
                "sessionId": AnyCodable(sessionId ?? ""),
                "timestamp": AnyCodable(Date().timeIntervalSince1970),
                "timezone": AnyCodable(TimeZone.current.identifier),
            ]

            try await agentWebSocket.sendMessage(message, context: context)

            // Delay to let the listening_stop sound finish before playing typing sound
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms

            // Play "agent typing" feedback now that message is sent (waiting for response)
            audioFeedback.playAgentTypingFeedback()
        } catch {
            setState(.error(error.localizedDescription))
        }
    }

    /// Set muted state (only affects TTS/sounds, not voice recording)
    func setMuted(_ muted: Bool) {
        isMuted = muted

        // Propagate to streaming audio player
        streamingAudioPlayer?.setMuted(muted)

        // Stop speaking immediately if muted
        if muted && state == .speaking {
            streamingAudioPlayer?.stop()
            setState(.idle)
        }
    }

    /// Stop current TTS without affecting mute state (skip this message)
    func stopSpeaking() {
        guard state == .speaking else { return }
        streamingAudioPlayer?.stop()
        setState(.idle)
    }

    /// Set privacy mode (TTS off, haptics only)
    func setPrivacyMode(_ enabled: Bool) {
        isPrivacyMode = enabled

        if enabled && state == .speaking {
            streamingAudioPlayer?.stop()
            setState(.idle)
        }
    }

    // MARK: - Private Methods

    private func setState(_ newState: ConversationState) {
        let oldState = state
        state = newState

        // Announce state change for accessibility (throttled)
        if oldState != newState {
            announceStateChange(newState)
        }
    }

    private func emitEvent(_ event: ConversationEvent) {
        onEvent?(event)
    }

    private func handleSpeakingFinished() {
        if state == .speaking || state == .connecting {
            setState(.idle)
        }
    }

    // MARK: - Agent Event Handling

    /// Handles all events from the AgentWebSocketManager event stream.
    /// Replaces the previous 7 separate callback closures with a single sequential handler.
    private func handleAgentEvent(_ event: AgentEvent) {
        switch event {
        case .connectionAck(let ack):
            if let serverSessionId = ack.sessionId ?? ack.connectionId {
                sessionId = serverSessionId
            }
            // Stay in .connecting — the button remains disabled with "Connecting..."
            // until the first agent message arrives and transitions to .speaking.
            // This prevents the button appearing active while the intro message loads.

        case .streamChunk(let chunk):
            let responseId = currentAgentResponseId ?? UUID()
            currentAgentResponseId = responseId
            emitEvent(.agentDelta(chunk.chunk, id: responseId))
            if chunk.complete == true {
                handleAgentResponseComplete(id: responseId)
            }

        case .agentResponse(let response):
            audioFeedback.stopProcessingPulse()
            let responseId = currentAgentResponseId ?? UUID()
            emitEvent(.agentFinal(response.message, id: responseId))
            if streamingAudioPlayer?.isPlaying != true && streamingAudioPlayer?.isBuffering != true {
                setState(.idle)
            }
            currentAgentResponseId = nil

        case .audioChunk(let chunk):
            audioFeedback.stopProcessingPulse()
            Logger.debug("ConversationCoordinator: Audio chunk received, player=\(streamingAudioPlayer != nil), isPlaying=\(streamingAudioPlayer?.isPlaying ?? false)")
            streamingAudioPlayer?.appendAudioChunk(chunk.audio)

        case .audioComplete(let complete):
            let responseId = currentAgentResponseId ?? UUID()
            emitEvent(.agentFinal(complete.responseText, id: responseId))
            // Extract voice speed from server data (may arrive as Double or Int)
            if let data = complete.data,
               let speedValue = (data["voice_speed"]?.value as? Double) ?? (data["voice_speed"]?.value as? Int).map(Double.init) {
                streamingAudioPlayer?.playbackRate = Float(speedValue)
            }
            // Silence the voice_status bridge right before agent TTS starts so
            // they don't overlap. Safe no-op if it already finished naturally.
            stopVoiceStatusSpeech()
            playAccumulatedAudio()
            currentAgentResponseId = nil

        case .error(let error):
            audioFeedback.stopProcessingPulse()
            setState(.error(error.error))
            audioFeedback.feedbackForStateChange(.error(error.error))

        case .acknowledgment(let ack):
            Logger.info("ConversationCoordinator: Agent acknowledged, thinking...")
            if let text = ack.text, !text.isEmpty {
                emitEvent(.status(text))
            }

        case .voiceStatus(let payload):
            speakVoiceStatus(payload.text)
            emitEvent(.status(payload.text))

        case .permanentDisconnect:
            setState(.disconnected)
            stopVoiceStatusSpeech()
            emitEvent(.errorEvent("Connection lost. Please go back and try again."))
        }
    }

    // MARK: - Voice Status Bridge Audio

    /// Speak a short pre-response status message via on-device TTS. The
    /// utterance is kept brief on the server side (one short sentence);
    /// we play it immediately so the user hears feedback during the 2–3s
    /// window while the agent graph is still running. The first audio
    /// chunk from the agent response interrupts this.
    private func speakVoiceStatus(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stopVoiceStatusSpeech()  // cancel any earlier status still playing
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        voiceStatusSynthesizer.speak(utterance)
    }

    private func stopVoiceStatusSpeech() {
        if voiceStatusSynthesizer.isSpeaking {
            voiceStatusSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - STT Callbacks (ElevenLabs)

    private func setupSTTCallbacks() {
        // Handle transcription updates (partial and final)
        sttService.onTranscription = { [weak self] text, isFinal in
            guard let self = self else { return }
            guard self.isVoiceSessionActive else { return }

            // Always update the draft with the latest text so it's available
            // for finalization, even if state has already moved to .processing
            // (e.g., user tapped stop and we're waiting for the commit flush).
            self.transcriptStore?.updateDraft(text)

            if isFinal {
                // Committed transcript from VAD - auto-stop and process
                self.stopListeningAndProcess()
            }
        }

        // Handle STT errors — recover gracefully to idle so the user can try again
        sttService.onError = { [weak self] error in
            guard let self = self else { return }

            Logger.error("STT error: \(error.localizedDescription)")

            // Clean up voice session
            self.voiceService.stopRecording()
            self.voiceService.onAudioBuffer = nil
            self.isVoiceSessionActive = false
            self.transcriptStore?.discardDraft()

            // Show a concise, user-friendly message on the mic button.
            // The raw NSError descriptions are too technical.
            let userMessage = Self.friendlySTTError(error)
            self.setState(.error(userMessage))

            // Auto-recover to idle after a short delay so the user can retry
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                guard let self, case .error = self.state else { return }
                self.setState(.idle)
            }
        }

        // Handle STT disconnection
        sttService.onDisconnected = { [weak self] in
            guard let self = self else { return }

            // Only handle unexpected disconnections (not user-initiated)
            if self.isVoiceSessionActive && self.state == .listening {
                Logger.warning("STT disconnected unexpectedly")
                self.voiceService.stopRecording()
                self.voiceService.onAudioBuffer = nil
                self.isVoiceSessionActive = false
                self.transcriptStore?.discardDraft()
                self.setState(.idle)
            }
        }
    }

    private func handleAgentResponseComplete(id: UUID) {
        // Response is complete, transition to speaking if we have text
        if !isPrivacyMode {
            setState(.speaking)
        } else {
            setState(.idle)
        }
    }

    private func playAccumulatedAudio() {
        guard !isPrivacyMode, !isMuted else {
            Logger.info("ConversationCoordinator: Skipping audio - privacy=\(isPrivacyMode), muted=\(isMuted)")
            setState(.idle)
            return
        }

        setState(.speaking)
        streamingAudioPlayer?.playAccumulatedAudio()
    }

    // MARK: - Accessibility Announcements

    private var lastAnnouncementTime: Date = .distantPast
    private let announcementDebounceInterval: TimeInterval = 0.8

    private func announceStateChange(_ state: ConversationState) {
        let now = Date()
        guard now.timeIntervalSince(lastAnnouncementTime) >= announcementDebounceInterval else {
            return // Throttle announcements
        }

        lastAnnouncementTime = now

        // Post accessibility announcement
        UIAccessibility.post(
            notification: .announcement,
            argument: state.accessibilityAnnouncement
        )
    }

    // MARK: - App Lifecycle

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appWillResignActive() {
        // Stop all audio activity when app goes to background
        if state == .listening {
            voiceService.stopRecording()
            voiceService.onAudioBuffer = nil
            sttService.disconnect()
            isVoiceSessionActive = false
            transcriptStore?.discardDraft()
        }

        if state == .speaking {
            streamingAudioPlayer?.stop()
        }

        // Emit paused status
        if state != .idle && state != .disconnected {
            emitEvent(.status("Paused"))
            setState(.idle)
        }
    }

    @objc private func appDidBecomeActive() {
        // Could auto-reconnect here if needed
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Connection Status

extension ConversationCoordinator {
    /// Whether currently connected to the backend
    var isConnected: Bool {
        agentWebSocket.isConnected
    }
}

// MARK: - Error Helpers

extension ConversationCoordinator {
    /// Maps raw STT/network errors to concise, user-friendly strings.
    static func friendlySTTError(_ error: Error) -> String {
        // ElevenLabs-specific errors — use their descriptions directly
        if let sttError = error as? ElevenLabsSTTError {
            switch sttError {
            case .resourceExhausted:
                return "Voice quota exceeded. Try again later."
            case .idleTimeout:
                return "Voice session timed out."
            default:
                return sttError.localizedDescription
            }
        }

        let nsError = error as NSError

        // Generic network / timeout
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return "Voice connection timed out."
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "No internet connection."
            default:
                return "Voice connection lost."
            }
        }

        // POSIX socket errors (e.g., connection reset)
        if nsError.domain == NSPOSIXErrorDomain {
            return "Voice connection lost."
        }

        return "Voice error. Tap to try again."
    }
}
