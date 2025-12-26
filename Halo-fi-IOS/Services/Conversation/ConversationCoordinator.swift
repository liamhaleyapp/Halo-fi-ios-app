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
    private var speechService: SpeechSynthesisService?
    private var audioFeedback: AudioFeedbackService?

    // MARK: - Private State

    private var currentAgentResponseId: UUID?
    private var pendingRetryMessage: String?

    // MARK: - Initialization

    private init() {
        self.voiceService = VoiceService.shared
        self.agentWebSocket = AgentWebSocketManager.shared

        setupNotifications()
        setupAgentCallbacks()
    }

    // MARK: - Dependency Injection (for services created after init)

    func configure(speechService: SpeechSynthesisService, audioFeedback: AudioFeedbackService) {
        self.speechService = speechService
        self.audioFeedback = audioFeedback

        speechService.onSpeakingFinished = { [weak self] in
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

            // Try to connect voice service (non-blocking - voice is optional)
            do {
                try await voiceService.connect(userId: sessionId!)
            } catch {
                Logger.warning("Voice service unavailable: \(error.localizedDescription). Text mode will still work.")
            }

            setState(.idle)
            emitEvent(.status("Connected to Halo"))
        } catch {
            setState(.error(error.localizedDescription))
            emitEvent(.errorEvent("Failed to connect: \(error.localizedDescription)"))
        }
    }

    /// Disconnect from the backend
    func disconnect() {
        voiceService.stopRecording()
        voiceService.disconnect()
        agentWebSocket.disconnect()
        speechService?.stop()

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
    }

    /// Start listening (voice mode)
    func startListening() async {
        guard state == .idle || state == .speaking else { return }
        guard interactionMode == .voice else { return }

        // Check if voice service is connected
        guard voiceService.isConnected else {
            setState(.error("Voice not available"))
            emitEvent(.errorEvent("Voice service is not connected. Please use text input instead."))
            return
        }

        // Stop TTS if speaking
        if state == .speaking {
            speechService?.stop()
        }

        // Check permission
        let permissionManager = PermissionManager.shared
        let status = await permissionManager.requestMicrophonePermission()

        guard status == .granted else {
            setState(.permissionNeeded)
            return
        }

        do {
            setState(.listening)
            audioFeedback?.feedbackForStateChange(.listening)
            try await voiceService.startRecording()
        } catch {
            setState(.error(error.localizedDescription))
            emitEvent(.errorEvent("Failed to start recording: \(error.localizedDescription)"))
        }
    }

    /// Stop listening (voice mode)
    func stopListening() {
        guard state == .listening else { return }

        voiceService.stopRecording()
        audioFeedback?.feedbackForStateChange(.processing)
        setState(.processing)
    }

    /// Send a text message
    func sendText(_ message: String) async {
        guard !message.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard state == .idle || state == .listening else { return }

        // Stop listening if active
        if state == .listening {
            voiceService.stopRecording()
        }

        // Emit user message event
        emitEvent(.userText(message))

        // Send to agent
        setState(.processing)

        do {
            currentAgentResponseId = UUID()

            let context: [String: AnyCodable] = [
                "platform": AnyCodable("ios"),
                "sessionId": AnyCodable(sessionId ?? ""),
                "timestamp": AnyCodable(Date().timeIntervalSince1970)
            ]

            try await agentWebSocket.sendMessage(message, context: context)
        } catch {
            setState(.error(error.localizedDescription))
            emitEvent(.errorEvent("Failed to send message: \(error.localizedDescription)"))
        }
    }

    /// Set muted state
    func setMuted(_ muted: Bool) {
        isMuted = muted

        // Propagate to speech service
        speechService?.setMuted(muted)

        // Stop recording if listening
        if muted && state == .listening {
            voiceService.stopRecording()
            setState(.idle)
        }

        // Stop speaking immediately if muted
        if muted && state == .speaking {
            speechService?.stop()
            setState(.idle)
        }
    }

    /// Stop current TTS without affecting mute state (skip this message)
    func stopSpeaking() {
        guard state == .speaking else { return }
        speechService?.stop()
        setState(.idle)
    }

    /// Set privacy mode (TTS off, haptics only)
    func setPrivacyMode(_ enabled: Bool) {
        isPrivacyMode = enabled

        if enabled && state == .speaking {
            speechService?.stop()
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
        if state == .speaking {
            setState(.idle)
        }
    }

    // MARK: - Agent WebSocket Callbacks

    private func setupAgentCallbacks() {
        // Handle streaming chunks
        agentWebSocket.onStreamChunk = { [weak self] chunk in
            Task { @MainActor in
                guard let self = self else { return }

                let responseId = self.currentAgentResponseId ?? UUID()
                self.currentAgentResponseId = responseId

                self.emitEvent(.agentDelta(chunk.chunk, id: responseId))

                // Check if complete
                if chunk.complete == true {
                    // Final will be sent separately or we finalize here
                    self.handleAgentResponseComplete(id: responseId)
                }
            }
        }

        // Handle complete responses
        agentWebSocket.onAgentResponse = { [weak self] response in
            Task { @MainActor in
                guard let self = self else { return }

                let responseId = self.currentAgentResponseId ?? UUID()

                // Emit final event
                self.emitEvent(.agentFinal(response.message, id: responseId))

                // Speak the response
                self.speakAgentResponse(response.message)

                self.currentAgentResponseId = nil
            }
        }

        // Handle errors
        agentWebSocket.onError = { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }

                self.setState(.error(error.error))
                self.emitEvent(.errorEvent(error.error))
                self.audioFeedback?.feedbackForStateChange(.error(error.error))
            }
        }

        // Handle connection ack
        agentWebSocket.onConnectionAck = { [weak self] ack in
            Task { @MainActor in
                guard let self = self else { return }

                if let serverSessionId = ack.sessionId ?? ack.connectionId {
                    self.sessionId = serverSessionId
                }
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

    private func speakAgentResponse(_ text: String) {
        guard !isPrivacyMode else {
            setState(.idle)
            return
        }

        // Don't speak if muted (handles mute during .processing)
        guard !isMuted else {
            setState(.idle)
            return
        }

        guard !UIAccessibility.isVoiceOverRunning else {
            // VoiceOver is on, don't use TTS (let user read transcript)
            setState(.idle)
            return
        }

        setState(.speaking)
        speechService?.speak(text)
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
        }

        if state == .speaking {
            speechService?.stop()
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
