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

    // MARK: - Transcript Store (for draft management)

    private var transcriptStore: ConversationTranscriptStore?

    // MARK: - Private State

    private var currentAgentResponseId: UUID?
    private var pendingRetryMessage: String?
    private var isVoiceSessionActive = false
    private var agentEventTask: Task<Void, Never>?

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
        } catch {
            setState(.error(error.localizedDescription))
            emitEvent(.errorEvent("Failed to connect: \(error.localizedDescription)"))
        }
    }

    /// Disconnect from the backend
    func disconnect() {
        agentEventTask?.cancel()
        agentEventTask = nil

        voiceService.stopRecording()
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
        emitEvent(.errorEvent("Voice unavailable: \(error.localizedDescription)"))
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
            emitEvent(.errorEvent("Failed to send message: \(error.localizedDescription)"))
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
            playAccumulatedAudio()
            currentAgentResponseId = nil

        case .error(let error):
            audioFeedback.stopProcessingPulse()
            setState(.error(error.error))
            emitEvent(.errorEvent(error.error))
            audioFeedback.feedbackForStateChange(.error(error.error))

        case .acknowledgment(let ack):
            Logger.info("ConversationCoordinator: Agent acknowledged, thinking...")
            if let text = ack.text, !text.isEmpty {
                emitEvent(.status(text))
            }

        case .permanentDisconnect:
            setState(.disconnected)
            emitEvent(.errorEvent("Connection lost. Please go back and try again."))
        }
    }

    // MARK: - STT Callbacks (ElevenLabs)

    private func setupSTTCallbacks() {
        // Handle transcription updates (partial and final)
        sttService.onTranscription = { [weak self] text, isFinal in
            guard let self = self else { return }
            guard self.isVoiceSessionActive else { return }

            if isFinal {
                // Committed transcript from VAD - auto-stop and process
                self.stopListeningAndProcess()
            } else {
                // Partial transcript - update draft in UI
                self.transcriptStore?.updateDraft(text)
            }
        }

        // Handle STT errors
        sttService.onError = { [weak self] error in
            guard let self = self else { return }

            Logger.error("STT error: \(error.localizedDescription)")

            // Clean up voice session
            self.voiceService.stopRecording()
            self.voiceService.onAudioBuffer = nil
            self.isVoiceSessionActive = false
            self.transcriptStore?.discardDraft()

            // Show error to user
            self.setState(.error(error.localizedDescription))
            self.emitEvent(.errorEvent("Voice transcription failed: \(error.localizedDescription)"))
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
