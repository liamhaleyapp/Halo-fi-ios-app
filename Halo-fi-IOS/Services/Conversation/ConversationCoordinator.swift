//
//  ConversationCoordinator.swift
//  Halo-fi-IOS
//
//  THE authority for conversation state. Owns:
//  - Session ID
//  - Connection lifecycle
//  - Event stream
//  - Audio session transitions
//  - Full-duplex capture and playback in hands-free mode
//
//  UI calls only public methods; internal services (VoiceService, AgentWebSocketManager) are private.
//

import Foundation
import UIKit
import AVFoundation

@Observable
@MainActor
final class ConversationCoordinator {
    // MARK: - Singleton

    static let shared = ConversationCoordinator()

    // MARK: - Public State (Read-Only)

    private(set) var state: ConversationState = .idle
    private(set) var sessionId: String?
    private(set) var workflowActivity: WorkflowActivityPayload?
    /// Mutes Halo's spoken responses (TTS playback). Distinct from
    /// `isMicMuted` which only affects the user's mic input.
    private(set) var isMuted: Bool = false
    /// Hands-free only — pauses forwarding of mic audio to STT
    /// without disconnecting the WebSocket. Tapping the big button
    /// in hands-free mode toggles this. No-op in push-to-talk.
    private(set) var isMicMuted: Bool = false
    private(set) var isPrivacyMode: Bool = false
    private(set) var interactionMode: InteractionMode = .voice
    /// Selected by the user in Settings → Preferences. Set externally
    /// via `setConversationMode(_:)` so the view model can keep the
    /// coordinator in sync with @AppStorage. Defaults to push-to-talk
    /// to match historical behavior for users who never opted in.
    private(set) var conversationMode: ConversationMode = .handsFree

    // MARK: - Event Stream

    /// Store subscribes to this to receive events
    var onEvent: ((ConversationEvent) -> Void)?

    // MARK: - Private Services

    private let voiceService: VoiceService
    private let agentWebSocket: any AgentWebSocketManagerProtocol
    private var streamingAudioPlayer: StreamingAudioPlayer?
    private var audioFeedback: AudioFeedbackService = AudioFeedbackService()
    private let sttService: ElevenLabsSTTService

    // MARK: - Transcript Store (for draft management)

    private var transcriptStore: ConversationTranscriptStore?

    // MARK: - Private State

    private var currentAgentResponseId: UUID?

    // MARK: - WP7 turn correlation
    /// Client-generated id for the turn in flight. Every server event for
    /// it carries the same id; anything else is stale and dropped.
    private(set) var currentTurnId: String?
    private var cancelledTurnIds: [String] = []
    private var voiceTiming = VoiceTurnTiming()
    private let failureSpeaker = AVSpeechSynthesizer()
    private var lastDetectedSpeechUptime: TimeInterval?

    /// True while the full-screen voice modal is on screen (from any tab).
    /// The chat thread uses it to stay silent: a VoiceOver announcement of
    /// Halo's reply during a voice session would be picked up by the mic.
    private(set) var isVoiceModalPresented = false

    func setVoiceModalPresented(_ presented: Bool) {
        isVoiceModalPresented = presented
    }
    private var pendingRetryMessage: String?
    private var isVoiceSessionActive = false
    private var agentEventTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    private var sttWarmupTask: Task<Void, Never>?
    private var sttRecoveryTask: Task<Void, Never>?
    private var sttRecoveryAttempts = 0
    private var listenTask: Task<Void, Never>?
    private var resumeListeningTask: Task<Void, Never>?
    private var lifecycleID = UUID()
    private var connectionStartedAt: TimeInterval?
    private var greetingPlaybackRecorded = false
    /// Phase 12 — when true, connection_ack transitions us straight
    /// to .idle since no greeting will arrive. Reset on disconnect.
    private var skipGreetingForCurrentConnection = false
    /// Phase 12 — message queued by the caller while state was
    /// .connecting. Flushed once connection_ack lands and we're
    /// ready to send. Saves callers from racing the WS handshake.
    private var pendingInitialMessage: String?
    /// Set while the streaming player is playing a contextual
    /// acknowledgment ("Providing your full SSI status update.").
    /// When playback finishes, we transition state back to
    /// .processing instead of .idle so the input button doesn't
    /// flicker back to "Tap to talk" before the actual response
    /// audio arrives.
    private var isPlayingAcknowledgment = false

    // MARK: - Hands-free silence detection
    //
    // ElevenLabs Scribe v2's server-side VAD doesn't reliably fire
    // committed transcripts in our setup, so hands-free needs a
    // client-side fallback: track the RMS of incoming mic buffers,
    // mark when the user has spoken at least once during the current
    // listen, and auto-commit when we see silenceCommitInterval of
    // sub-threshold audio after that first speech.

    /// True the moment we've seen audio above the voice-activity
    /// threshold during the current listening turn. Prevents an
    /// initial silence (user takes a beat to start) from triggering
    /// an empty commit.
    private var hasDetectedSpeechInCurrentListen = false

    /// Timestamp of the most recent above-threshold buffer in this
    /// listening turn. Used to measure trailing silence.
    private var lastVoiceActivityAt: Date?

    /// RMS magnitude (linear, 0...1) above which we consider a
    /// buffer to contain voice. 0.04 sits comfortably above the noise
    /// floor of most setups (Mac/iPhone mics in a quiet room hover
    /// around 0.01–0.03 from fan/hvac/breathing) without missing
    /// normal conversational speech (typically 0.08–0.3 RMS).
    /// First version used 0.012 and never committed because ambient
    /// noise stayed above threshold continuously.
    private let voiceActivityRMSThreshold: Float = 0.04

    /// How long after the user's last detected voice activity we wait
    /// before auto-committing the turn. ChatGPT/Gemini commit at
    /// ~600-700ms; we sit at 0.5s to feel snappy on a real device.
    /// If users start reporting cut-offs mid-sentence, nudge back up
    /// to 0.7s — we previously sat there but it felt sluggish in
    /// hands-free testing.
    /// WP7 — the SERVER (Scribe VAD, 0.8 s) ends the turn; this timer is
    /// only the fallback when its commit never arrives, so it sits at 1.2 s.
    private let silenceCommitInterval: TimeInterval = 1.2

    /// WP7 — commits shorter than this are treated as noise (a cough, a
    /// door) and the turn keeps listening.
    private var minSpeechDuration: TimeInterval = 0.2
    private var speechSecondsInCurrentListen: TimeInterval = 0

    // MARK: - Hands-free barge-in
    //
    // When the user starts talking while Halo is mid-response, we
    // immediately stop the TTS playback and switch to listening —
    // VoIP-style interruption. Implementation: keep voiceService
    // recording across all hands-free states (not just .listening),
    // route buffers to a barge-in detector during .speaking, and
    // call streamingAudioPlayer.stop() the moment we see sustained
    // voice activity above bargeInThreshold.

    private var bargeInDetector = VoiceBargeInDetector()

    private var interruptionAudio = VoiceInterruptionAudio<AVAudioPCMBuffer>()

    /// Set by pause/stop paths that stop the player deliberately. The
    /// player's "finished" callback arrives one tick later; without this it
    /// would restart the microphone after the session was already ended.
    private var suppressNextAutoResume = false

    /// Distinguishes an interrupted acknowledgment from one that completed.
    private var bargeInRequested: Bool = false

    /// Physical playback completion, used to measure the handoff to the ready cue.
    private var lastSpeakingEndedAt: Date?

    // MARK: - Hands-free stall-proofing + idle watchdog
    //
    // Session minutes are metered by wall-clock connection time (server
    // heartbeat every 10s), so any path that strands hands-free in a
    // silent .idle/.error state burns the user's quota with zero signal —
    // the worst failure shape for a blind user. Two defenses:
    //   1. Silent dead-ends (empty commit, agent error, guardrail
    //      rejection) recover back to .listening with an audio cue
    //      instead of stalling.
    //   2. An idle watchdog warns after `idleWarningInterval` without
    //      meaningful activity and ends the session at `idleEndInterval`.
    private var consecutiveEmptyHandsFreeTurns = 0
    private var lastMeaningfulActivityAt: Date?
    private var idleWarningIssued = false
    private var idleWatchdogTask: Task<Void, Never>?
    private let idleWarningInterval: TimeInterval = 105
    private let idleEndInterval: TimeInterval = 135

    /// Something real happened (user sent a turn, Halo finished speaking,
    /// session connected) — push the idle watchdog out.
    private func markMeaningfulActivity() {
        lastMeaningfulActivityAt = Date()
        idleWarningIssued = false
    }

    private func startIdleWatchdog() {
        idleWatchdogTask?.cancel()
        markMeaningfulActivity()
        idleWatchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard let last = self.lastMeaningfulActivityAt else { continue }
                // Never end mid-turn — only quiet states count as idle.
                switch self.state {
                case .idle, .listening, .error:
                    break
                default:
                    continue
                }
                let idleFor = Date().timeIntervalSince(last)
                if idleFor >= self.idleEndInterval {
                    Logger.info("Idle watchdog: ending session after \(Int(idleFor))s of inactivity")
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Ending the conversation to save your minutes. Tap to start again."
                    )
                    self.audioFeedback.feedbackForStateChange(.disconnected)
                    self.disconnect()
                    return
                }
                if idleFor >= self.idleWarningInterval, !self.idleWarningIssued {
                    self.idleWarningIssued = true
                    Logger.info("Idle watchdog: warning after \(Int(idleFor))s of inactivity")
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Still there? I'll end the conversation soon to save your minutes."
                    )
                    self.audioFeedback.playSuccessFeedback()
                }
            }
        }
    }

    // MARK: - Recording capture (training data)
    //
    // Every listening turn's mic buffers are also accumulated here.
    // After the transcript is sent to the agent, we fire-and-forget
    // a background upload to /agent/recordings/upload — encoding +
    // network never block the conversation path. Failures log but
    // don't surface to the user.

    private let recordingUploader = RecordingUploader()
    private var capturedBuffers: [AVAudioPCMBuffer] = []
    /// Monotonic per-session counter so each turn lands at a stable
    /// path in storage ({user}/{session}/turn_N.wav).
    private var recordingTurnNumber: Int = 0
    /// Turn number we last handed to RecordingUploader.upload — used
    /// by the agentResponse handler to PATCH the matching row.
    private var lastUploadedTurnNumber: Int?
    /// Wall-clock timestamp of when the user transcript was sent to
    /// the agent. Diffed against the agent's reply to compute
    /// response_time_ms for the recording.
    private var lastUserSendAt: Date?

    /// Hard cap on a single listening turn. Even if silence detection
    /// never fires (always-on background noise above threshold) we
    /// commit after this so the conversation always progresses.
    /// 45s: the old 12s cut off blind users mid-question (they often
    /// describe a purchase or a month in one breath). The cap only
    /// fires when the SERVER has gone quiet too — see
    /// serverCommitGrace — so a long monologue the STT is keeping up
    /// with is never chopped.
    private let maxListenDuration: TimeInterval = 45.0

    /// If the server committed a transcript segment this recently, the
    /// hard cap defers: the STT is still delivering, so the turn is
    /// alive and the server's own end-of-speech will close it.
    private let serverCommitGrace: TimeInterval = 5.0

    /// When the server last committed a transcript segment for the
    /// current turn. Reset at the start of every listen.
    private var lastServerCommitAt: Date?

    /// Hands-free safety net — if the user opens the conversation,
    /// hears the greeting, but never speaks, auto-commit anyway after
    /// this long so we don't burn the STT session forever.
    private let maxListenWithoutSpeech: TimeInterval = 30.0

    /// When the current listening turn started — used by the safety
    /// timeout above. Cleared by stopListeningAndProcess.
    private var listenStartedAt: Date?

    // MARK: - Initialization

    // Internal construction lets protocol tests use an isolated coordinator.
    init(agentWebSocket: (any AgentWebSocketManagerProtocol)? = nil,
         sttService: ElevenLabsSTTService? = nil) {
        self.voiceService = VoiceService.shared
        self.agentWebSocket = agentWebSocket ?? AgentWebSocketManager.shared
        self.sttService = sttService ?? ElevenLabsSTTService()

        setupNotifications()
        setupSTTCallbacks()
    }

    // MARK: - Dependency Injection (for services created after init)

    func configure(
        streamingAudioPlayer: StreamingAudioPlayer,
        audioFeedback: AudioFeedbackService,
        transcriptStore: ConversationTranscriptStore
    ) {
        self.streamingAudioPlayer?.onPlaybackStarted = nil
        self.streamingAudioPlayer?.onPlaybackFinished = nil
        self.streamingAudioPlayer?.onPlaybackFailed = nil
        self.streamingAudioPlayer?.onBufferPlaybackStarted = nil
        self.streamingAudioPlayer?.stopAndDiscardPending()
        self.streamingAudioPlayer = streamingAudioPlayer
        self.audioFeedback = audioFeedback
        self.transcriptStore = transcriptStore

        // WP7 — .speaking only once the player has accepted a buffer.
        streamingAudioPlayer.onPlaybackStarted = { [weak self] in
            guard let self, self.sessionId != nil else { return }
            switch self.state {
            case .processing, .idle, .connecting:
                self.setState(.speaking)
                self.startInterruptionCapture()
            default:
                break
            }
        }
        streamingAudioPlayer.onBufferPlaybackStarted = { [weak self] marker, outputEnabled in
            guard let self else { return }
            if marker.turnId == nil, !marker.isError, !marker.isAcknowledgment,
               !self.greetingPlaybackRecorded, let started = self.connectionStartedAt {
                self.greetingPlaybackRecorded = true
                Diagnostics.send("voice_greeting_playback", [
                    "connect_to_playback_ms": String(Int((ProcessInfo.processInfo.systemUptime - started) * 1000)),
                    "output_enabled": String(outputEnabled)
                ])
            }
            guard let fields = self.voiceTiming.playback(marker, at: ProcessInfo.processInfo.systemUptime,
                                                         outputEnabled: outputEnabled) else { return }
            Logger.info("Voice playback timing: \(fields)")
            Diagnostics.send("voice_playback", fields)
        }
        streamingAudioPlayer.onPlaybackFailed = { [weak self] in
            self?.handleAudioDeliveryFailure("Voice audio is unavailable. Please try again later, or read the answer in chat.")
        }
        streamingAudioPlayer.onPlaybackFinished = { [weak self] in
            self?.handleSpeakingFinished()
        }
    }

    // MARK: - Public API

    /// Connect to the backend.
    ///
    /// Phase 12 — pass ``skipGreeting: true`` when a quick-action
    /// flow is about to send a pre-prompt; the backend will skip
    /// its initial greeting so the user hears the answer to their
    /// tap, not a "Good evening" speech first.
    func connect(
        skipGreeting: Bool = false,
        customGreetingId: String? = nil
    ) async {
        guard state == .idle || state == .disconnected else { return }

        // Phase 12 — store the flag so connection_ack handling can
        // transition straight to .idle (otherwise state stays in
        // .connecting forever waiting for an intro message that
        // will never arrive, and queued prompts silently drop).
        // Phase 9c — a customGreetingId means the backend WILL send
        // a greeting (just not the welcome), so we don't want
        // .connecting to short-circuit to .idle the way it does for
        // skip_greeting. Treat custom greetings like the welcome
        // for state-transition purposes.
        self.skipGreetingForCurrentConnection = (
            skipGreeting && (customGreetingId?.isEmpty ?? true)
        )

        lifecycleID = UUID()
        let lifecycle = lifecycleID
        sttRecoveryAttempts = 0
        connectionStartedAt = ProcessInfo.processInfo.systemUptime
        greetingPlaybackRecorded = false
        suppressNextAutoResume = false
        lastSpeakingEndedAt = nil
        streamingAudioPlayer?.resumeAcceptingChunks()
        setState(.connecting)
        sessionId = UUID().uuidString

        do {
            try await agentWebSocket.connect(
                skipGreeting: skipGreeting,
                customGreetingId: customGreetingId
            )

            guard lifecycleID == lifecycle, !Task.isCancelled else { return }
            // Capture this stream, never a replacement connection's stream.
            let events = agentWebSocket.events
            agentEventTask?.cancel()
            agentEventTask = Task { [weak self] in
                guard let self else { return }
                for await event in events {
                    guard !Task.isCancelled, self.lifecycleID == lifecycle else { break }
                    self.handleAgentEvent(event)
                }
            }

            // Warm the engine without forwarding pre-cue audio to recognition.
            prewarmTask?.cancel()
            prewarmTask = Task { [weak self] in
                guard let self, self.lifecycleID == lifecycle else { return }
                do {
                    try self.voiceService.preWarmCapture()
                } catch {
                    Logger.debug("ConversationCoordinator: Pre-warm skipped")
                }
            }

            startIdleWatchdog()
        } catch {
            guard lifecycleID == lifecycle, !Task.isCancelled else { return }
            setState(.error(error.localizedDescription))
        }
    }

    /// Disconnect from the backend
    func disconnect() {
        workflowActivity = nil
        lifecycleID = UUID()
        sttRecoveryTask?.cancel()
        sttRecoveryTask = nil
        connectionStartedAt = nil
        listenTask?.cancel()
        listenTask = nil
        resumeListeningTask?.cancel()
        resumeListeningTask = nil
        sttWarmupTask?.cancel()
        sttWarmupTask = nil
        sttService.onSessionReady = nil
        cancelSpeechFinalization()
        voiceTiming.reset()
        lastDetectedSpeechUptime = nil
        agentEventTask?.cancel()
        agentEventTask = nil
        prewarmTask?.cancel()
        prewarmTask = nil
        idleWatchdogTask?.cancel()
        idleWatchdogTask = nil
        consecutiveEmptyHandsFreeTurns = 0

        // Phase 12 — clear quick-action state so a fresh connect
        // doesn't replay a stale prompt.
        skipGreetingForCurrentConnection = false
        pendingInitialMessage = nil
        isPlayingAcknowledgment = false
        // Reset hands-free mute so re-opening the conversation always
        // starts with the mic live.
        isMicMuted = false
        // Clear silence-detection + barge-in state so the next
        // conversation starts with a fresh slate.
        hasDetectedSpeechInCurrentListen = false
        lastVoiceActivityAt = nil
        listenStartedAt = nil
        bargeInDetector.reset()
        bargeInRequested = false
        interruptionAudio.reset()
        speechSecondsInCurrentListen = 0
        currentTurnId = nil
        // Drop any captured audio for the next conversation. Note we
        // do not reset recordingTurnNumber here — it's bound to the
        // session and we get a new sessionId on the next connect, so
        // the storage path stays unique either way.
        capturedBuffers = []
        recordingTurnNumber = 0
        lastUploadedTurnNumber = nil
        lastUserSendAt = nil

        // Stop the thinking-pulse haptic explicitly here too —
        // setState below will catch it via the leave-processing
        // guard, but if state was already .idle when disconnect was
        // called the haptic could otherwise be left running by an
        // earlier failure path.
        audioFeedback.stopProcessingPulse()

        voiceService.onAudioBuffer = nil
        voiceService.stopRecording()
        voiceService.teardownCapture()
        sttService.disconnect()
        agentWebSocket.disconnect()
        // stopAndDiscardPending (vs plain stop) closes the chunk gate
        // so any audio_chunk / audio_complete events still in flight
        // through the WebSocket / event-task pipeline don't sneak past
        // disconnect and resurrect playback after the user has left
        // the conversation. resumeAcceptingChunks() runs on the next
        // sendTextInternal so a fresh conversation starts clean.
        suppressNextAutoResume = true
        streamingAudioPlayer?.stopAndDiscardPending()
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

    /// Start exactly one listen transition, with a ready recognizer and microphone.
    func startListening() async {
        if case .error = state, agentWebSocket.isConnected {
            failureSpeaker.stopSpeaking(at: .immediate)
            setState(.idle)
        }
        if let pending = listenTask { await pending.value; return }
        guard state == .idle || state == .speaking else { return }
        guard interactionMode == .voice, sessionId != nil, agentWebSocket.isConnected else { return }
        let lifecycle = lifecycleID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.prepareListening(lifecycle: lifecycle)
        }
        listenTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if lifecycleID == lifecycle { listenTask = nil }
    }

    private func prepareListening(lifecycle: UUID) async {
        guard lifecycleID == lifecycle, !Task.isCancelled else { return }
        if streamingAudioPlayer?.isPlaying == true || streamingAudioPlayer?.isBuffering == true { return }
        setState(.connecting)
        let status = await PermissionManager.shared.requestMicrophonePermission()
        guard lifecycleID == lifecycle, !Task.isCancelled else { return }
        guard status == .granted else { setState(.permissionNeeded); return }
        do {
            try await connectWithTimeout()
            guard lifecycleID == lifecycle, !Task.isCancelled,
                  state == .connecting, agentWebSocket.isConnected else { return }
            try beginListenTurn(lifecycle: lifecycle)
        } catch {
            guard lifecycleID == lifecycle, !Task.isCancelled else { return }
            handleVoiceSetupError(error)
        }
    }

    /// Pre-connect recognition while the greeting plays. It sends no mic audio.
    private func warmSpeechRecognition() {
        guard interactionMode == .voice,
              PermissionManager.shared.isMicrophonePermissionGranted,
              sttWarmupTask == nil else { return }
        let lifecycle = lifecycleID
        sttWarmupTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.connectWithTimeout() }
            catch { Logger.debug("Speech warm-up unavailable; next listen can retry") }
            if self.lifecycleID == lifecycle { self.sttWarmupTask = nil }
        }
    }

    private func beginListenTurn(lifecycle: UUID) throws {
        lastDetectedSpeechUptime = nil
        hasDetectedSpeechInCurrentListen = false
        lastVoiceActivityAt = nil
        lastServerCommitAt = nil
        speechSecondsInCurrentListen = 0
        let openingAudio = interruptionAudio.takeInterruptedAudio()
        // Normal input starts at the ready cue. Only a locally detected
        // interruption preserves opening words from before that cue.
        voiceService.onAudioBuffer = nil
        voiceService.discardPreroll()
        try voiceService.startRecording()
        guard lifecycleID == lifecycle, !Task.isCancelled,
              state == .connecting, sttService.isSessionReady else { return }
        listenStartedAt = Date()
        isVoiceSessionActive = true
        setState(.listening)
        audioFeedback.feedbackForStateChange(.listening)
        voiceService.onAudioBuffer = { [weak self] buffer in
            guard let self, self.lifecycleID == lifecycle, !self.isMicMuted else { return }
            self.routeAudioBuffer(buffer)
        }
        for buffer in openingAudio { routeAudioBuffer(buffer) }
        var fields = ["session_id": sessionId ?? "", "mode": conversationMode.rawValue]
        if let endedAt = lastSpeakingEndedAt {
            fields["speech_end_to_ready_ms"] = String(Int(Date().timeIntervalSince(endedAt) * 1000))
        }
        Diagnostics.send("voice_listen_ready", fields)
    }

    private func handleVoiceSetupError(_ error: Error) {
        // Clean up on failure
        sttService.onSessionReady = nil
        sttService.disconnect()
        voiceService.onAudioBuffer = nil
        isVoiceSessionActive = false

        voiceService.stopRecording()
        setState(.error(Self.friendlySTTError(error)))
    }

    // MARK: - Connect watchdog

    /// Race-with-timeout error. Conforms to `LocalizedError` so the
    /// existing `handleVoiceSetupError` path renders the user-facing
    /// message via `error.localizedDescription` — no special-casing
    /// needed in the catch branch.
    private enum ConnectError: LocalizedError {
        case timeout
        var errorDescription: String? {
            switch self {
            case .timeout: return "Couldn't connect"
            }
        }
    }

    /// Race the STT handshake against a `seconds`-second sleep so a
    /// stalled `sttService.connect()` (network flap, server hung)
    /// can't leave the user stuck on the `.connecting` spinner
    /// forever. Whichever child finishes first wins; the other is
    /// cancelled by the defer.
    private func connectWithTimeout(seconds: TimeInterval = 10) async throws {
        let service = sttService
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await service.connect()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ConnectError.timeout
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    // A local stop keeps transcript callbacks active until final speech arrives.
    // The deadline covers both queued audio sends and the final transcript wait.
    private var finalizationTask: Task<Void, Never>?
    private var finalizationID: UUID?
    private var audioSendTask: Task<Void, Never>?
    private var audioSendGeneration = UUID()
    private var queuedSpeechBuffers = VoiceAudioQueue<AVAudioPCMBuffer>()
    private var finalizationTimeoutTask: Task<Void, Never>?

    func stopListening() { stopListeningAndProcess() }

    private func cancelSpeechFinalization() {
        finalizationID = nil
        finalizationTimeoutTask?.cancel()
        finalizationTimeoutTask = nil
        failureSpeaker.stopSpeaking(at: .immediate)
        audioSendGeneration = UUID()
        queuedSpeechBuffers.removeAll()
        finalizationTask?.cancel()
        finalizationTask = nil
        audioSendTask?.cancel()
        audioSendTask = nil
    }

    private func enqueueSpeechAudio(_ buffer: AVAudioPCMBuffer) {
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        guard queuedSpeechBuffers.append(buffer, duration: duration) else {
            // Never send a silently truncated utterance, particularly a confirmation.
            Logger.warning("Voice audio backlog limit reached")
            Diagnostics.send("voice_audio_overflow", ["queued_ms": String(Int(queuedSpeechBuffers.duration * 1000))])
            failSpeechFinalization()
            return
        }
        guard audioSendTask == nil else { return }
        let generation = audioSendGeneration
        audioSendTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.audioSendGeneration == generation,
                  !self.queuedSpeechBuffers.isEmpty {
                guard let next = self.queuedSpeechBuffers.popFirst() else { break }
                await self.sttService.sendAudioBuffer(next)
            }
            if self.audioSendGeneration == generation { self.audioSendTask = nil }
        }
    }

    private func handleAudioDeliveryFailure(_ message: String) {
        // Prevent recovery tasks or late frames from restarting this failed turn.
        lastAnnouncementTime = Date()
        setState(.error(message))
        sttRecoveryTask?.cancel()
        sttRecoveryTask = nil
        sttWarmupTask?.cancel()
        sttWarmupTask = nil
        listenTask?.cancel()
        resumeListeningTask?.cancel()
        cancelSpeechFinalization()
        cancelCurrentTurn()
        isVoiceSessionActive = false
        voiceService.stopRecording()
        voiceService.onAudioBuffer = nil
        sttService.disconnect()
        streamingAudioPlayer?.stopAndDiscardPending()
        audioFeedback.stopProcessingPulse()
        isPlayingAcknowledgment = false
        emitEvent(.agentFinal(message, id: currentAgentResponseId ?? UUID()))
        currentAgentResponseId = nil
        Diagnostics.send("voice_audio_delivery_failed", [:])
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: message)
        } else if !isMuted && !isPrivacyMode {
            failureSpeaker.stopSpeaking(at: .immediate)
            failureSpeaker.speak(AVSpeechUtterance(string: message))
        }
    }

    private func failSpeechFinalization() {
        Diagnostics.send("voice_input_finalization_failed")
        sttService.disconnect()
        handleRecognitionFailure(URLError(.timedOut), allowOutputToContinue: false,
            messageOverride: "I couldn't finish hearing that. Please try again.")
    }

    /// State-aware router for every mic buffer. Always invoked on
    /// MainActor (see `voiceService.onAudioBuffer` wiring).
    private var routerLogCounter: Int = 0
    private func routeAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Log every ~50th buffer (about 1/sec) so we can see what
        // state buffers are arriving in without spamming the console.
        // Critical for diagnosing why barge-in doesn't fire during
        // .speaking — confirms the handler is wired AND running.
        routerLogCounter += 1
        if routerLogCounter % 50 == 0 {
            let rms = Self.computeRMS(buffer)
            Logger.debug("Buffer router: state=\(state) mode=\(conversationMode.rawValue) muted=\(isMicMuted) RMS=\(String(format: "%.4f", rms))")
        }

        switch state {
        case .listening:
            if Self.computeRMS(buffer) >= voiceActivityRMSThreshold {
                lastDetectedSpeechUptime = ProcessInfo.processInfo.systemUptime
            }
            // Send to STT, tap silence detection, AND accumulate the
            // raw buffer for post-turn training-data upload. The
            // upload itself runs background-detached after the turn
            // is committed — appending here is the cheap part.
            enqueueSpeechAudio(buffer)
            processAudioBufferForSilenceDetection(buffer)
            capturedBuffers.append(buffer)

        case .speaking, .processing:
            guard conversationMode == .handsFree, finalizationID == nil else { return }
            _ = interruptionAudio.append(buffer, duration: Double(buffer.frameLength) / buffer.format.sampleRate)
            processAudioBufferForBargeIn(buffer)

        case .connecting where interruptionAudio.isInterrupted:
            // Preserve the user's words if recognition is reconnecting after
            // local playback stopped. Never silently truncate a long request.
            if !interruptionAudio.append(buffer, duration: Double(buffer.frameLength) / buffer.format.sampleRate) {
                interruptionAudio.reset()
                handleRecognitionFailure(URLError(.timedOut), allowOutputToContinue: false,
                    messageOverride: "I couldn't keep up with that interruption. Please say it again.")
            }

        default:
            // .idle / .connecting / .error: ignore the
            // frame. We keep voiceService recording in hands-free so
            // the engine doesn't go through a teardown cycle between
            // turns, but there's nothing to do with the buffer here.
            break
        }
    }

    /// Capture must run during the greeting as well as subsequent answers.
    private func startInterruptionCapture() {
        guard conversationMode == .handsFree, !isMicMuted,
              PermissionManager.shared.isMicrophonePermissionGranted else { return }
        let lifecycle = lifecycleID
        do {
            voiceService.discardPreroll()
            try voiceService.startRecording()
            voiceService.onAudioBuffer = { [weak self] buffer in
                guard let self, self.lifecycleID == lifecycle, !self.isMicMuted else { return }
                self.routeAudioBuffer(buffer)
            }
        } catch {
            Diagnostics.send("voice_interruption_capture_failed")
            // Playback remains usable; the explicit Stop button is still active.
        }
    }

    private func processAudioBufferForBargeIn(_ buffer: AVAudioPCMBuffer) {
        let decision = bargeInDetector.observe(rms: Self.computeRMS(buffer),
            duration: Double(buffer.frameLength) / buffer.format.sampleRate)
        if decision == .interrupt {
            Diagnostics.send("voice_barge_in", ["source": "local_audio"])
            bargeIn(preserveOpeningAudio: true)
        }
    }

    /// Local cancellation is synchronous and independent of provider latency.
    /// Only this path resumes input; stopping the player must not also trigger
    /// a playback-finished callback and schedule a competing listen transition.
    private func bargeIn(preserveOpeningAudio: Bool) {
        guard state == .speaking || (state == .processing && finalizationID == nil) else { return }
        if preserveOpeningAudio { interruptionAudio.beginInterruption() }
        else { interruptionAudio.reset() }
        bargeInDetector.reset()
        isPlayingAcknowledgment = false
        cancelCurrentTurn(notifyPlaybackFinished: false)
        streamingAudioPlayer?.stopAndDiscardPending(notify: false)
        lastSpeakingEndedAt = Date()
        lastAnnouncementTime = Date()
        setState(.idle)
        guard conversationMode == .handsFree, !isMicMuted else { return }
        if sttService.isSessionReady {
            setState(.connecting)
            do { try beginListenTurn(lifecycle: lifecycleID) }
            catch { handleVoiceSetupError(error) }
        } else {
            resumeListeningTask?.cancel()
            let lifecycle = lifecycleID
            resumeListeningTask = Task { [weak self] in
                guard let self, self.lifecycleID == lifecycle, !Task.isCancelled else { return }
                await self.startListening()
            }
        }
    }

    /// Per-buffer silence-detection tap for hands-free auto-commit.
    /// Three commit triggers, in priority order:
    ///   1. Hard turn cap (maxListenDuration) — guarantees the
    ///      conversation progresses even if RMS stays above threshold
    ///      from ambient noise the whole time.
    ///   2. No-speech timeout (maxListenWithoutSpeech) — user opened
    ///      the conversation but never spoke; release the STT session.
    ///   3. Silence after speech (silenceCommitInterval) — the normal
    ///      end-of-utterance trigger.
    private func processAudioBufferForSilenceDetection(_ buffer: AVAudioPCMBuffer) {
        guard conversationMode == .handsFree, state == .listening else { return }
        // When the user mutes their mic mid-listen we must NOT treat the
        // resulting quiet stream as end-of-utterance — otherwise the
        // silence-after-speech timer fires, the turn auto-commits, and
        // state slips to .idle, which renders the mic button as
        // "Tap to Talk" instead of an unmute. The user then has to tap
        // three times (mute → idle → start listening → mute) before
        // they get back to a listening state. setMicMuted resets the
        // last-activity stamp on unmute so the timer starts fresh.
        guard !isMicMuted else { return }

        let now = Date()

        // Hard cap — fires regardless of whether we detected speech,
        // unless the server committed a segment in the last few
        // seconds (it is keeping up; let its end-of-speech end the turn).
        if let started = listenStartedAt,
           now.timeIntervalSince(started) > maxListenDuration {
            if let commit = lastServerCommitAt,
               now.timeIntervalSince(commit) < serverCommitGrace {
                // Deferred; re-evaluated on the next buffer.
            } else {
                Logger.info("Hands-free: hard turn cap hit at \(String(format: "%.1f", now.timeIntervalSince(started)))s — committing")
                stopListeningAndProcess()
                return
            }
        }

        // No-speech timeout — release STT if user is silent the
        // whole time.
        if !hasDetectedSpeechInCurrentListen,
           let started = listenStartedAt,
           now.timeIntervalSince(started) > maxListenWithoutSpeech {
            Logger.info("Hands-free: no-speech timeout — committing empty turn")
            stopListeningAndProcess()
            return
        }

        let rms = Self.computeRMS(buffer)

        if rms >= voiceActivityRMSThreshold {
            // Real voice activity. Mark the turn as "heard" so
            // silence after this point is meaningful.
            if !hasDetectedSpeechInCurrentListen {
                Logger.debug("Hands-free: first speech detected (RMS=\(String(format: "%.4f", rms)))")
            }
            hasDetectedSpeechInCurrentListen = true
            lastVoiceActivityAt = now
            // WP7 — accumulate how much actual speech this listen has
            // heard; sub-200 ms commits are treated as noise.
            if buffer.format.sampleRate > 0 {
                speechSecondsInCurrentListen += Double(buffer.frameLength) / buffer.format.sampleRate
            }
            return
        }

        // Below threshold — only matters if user already spoke.
        guard hasDetectedSpeechInCurrentListen,
              let lastActivity = lastVoiceActivityAt else { return }

        let silentFor = now.timeIntervalSince(lastActivity)
        if silentFor >= silenceCommitInterval {
            Logger.info("Hands-free: silence \(String(format: "%.1f", silentFor))s after speech — committing")
            stopListeningAndProcess()
        }
    }

    /// Linear RMS for a single AVAudioPCMBuffer's first channel.
    /// Returns 0 when the buffer has no float channel data.
    private static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameCount {
            let s = channelData[i]
            sum += s * s
        }
        return (sum / Float(frameCount)).squareRoot()
    }

    /// Internal: Stop listening after committed transcript (VAD auto-stop)
    private func stopListeningAndProcess(serverCommitted: Bool = false) {
        guard state == .listening, finalizationID == nil else { return }
        let token = UUID()
        finalizationID = token
        let endedAt = ProcessInfo.processInfo.systemUptime
        let lastSpeechAt = lastDetectedSpeechUptime
        let pendingAudio = audioSendTask
        setState(.processing)
        audioFeedback.feedbackForStateChange(.processing)
        hasDetectedSpeechInCurrentListen = false
        lastVoiceActivityAt = nil
        listenStartedAt = nil
        bargeInDetector.reset()
        if conversationMode != .handsFree {
            voiceService.stopRecording()
            voiceService.onAudioBuffer = nil
        }
        // Include queued socket sends in the deadline, not just the STT response.
        finalizationTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.finalizationID == token else { return }
            self.failSpeechFinalization()
        }
        finalizationTask = Task { [weak self] in
            guard let self else { return }
            await pendingAudio?.value
            guard !Task.isCancelled, self.finalizationID == token else { return }
            // Keep isVoiceSessionActive true while the final callback updates the draft.
            let confirmed: Bool
            if serverCommitted && self.transcriptStore?.hasUncommittedDraft == false {
                confirmed = true
            } else {
                confirmed = await self.sttService.commitAndWait()
            }
            guard !Task.isCancelled, self.finalizationID == token else { return }
            self.finalizationID = nil
            self.finalizationTimeoutTask?.cancel()
            self.finalizationTimeoutTask = nil
            self.finalizationTask = nil
            self.isVoiceSessionActive = false
            if self.conversationMode != .handsFree || !confirmed {
                self.sttService.disconnect()
            }
            guard confirmed, self.transcriptStore?.hasUncommittedDraft == false else {
                self.failSpeechFinalization()
                return
            }
            guard let finalText = self.transcriptStore?.finalizeDraft(),
                  !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.capturedBuffers = []
                self.setState(.idle)
                if self.conversationMode == .handsFree && !self.isMicMuted {
                    await self.startListening()
                }
                return
            }
            self.consecutiveEmptyHandsFreeTurns = 0
            self.sttRecoveryAttempts = 0
            self.markMeaningfulActivity()
            let buffers = self.capturedBuffers
            self.capturedBuffers = []
            self.recordingTurnNumber += 1
            self.lastUploadedTurnNumber = self.recordingTurnNumber
            self.lastUserSendAt = Date()
            self.recordingUploader.upload(buffers: buffers, sessionId: self.sessionId ?? "unknown",
                turnNumber: self.recordingTurnNumber, userTranscript: finalText)
            await self.sendTextInternal(finalText, turnEndedAt: endedAt, lastSpeechAt: lastSpeechAt)
        }
    }

    /// Backfill the agent_response field on the recording for the
    /// most recent uploaded turn. Both `.agentResponse` and
    /// `.audioComplete` (with body) call this — whichever arrives
    /// first wins, the second is a no-op because we clear the
    /// turn-number reference after firing.
    private func backfillRecordingAgentResponse(_ text: String) {
        guard let turn = lastUploadedTurnNumber, !text.isEmpty else { return }
        let elapsedMs: Int? = lastUserSendAt.map {
            Int(Date().timeIntervalSince($0) * 1000)
        }
        recordingUploader.setAgentResponse(
            turnNumber: turn,
            agentResponse: text,
            responseTimeMs: elapsedMs
        )
        lastUploadedTurnNumber = nil
        lastUserSendAt = nil
    }

    /// Send a text message (from text input).
    /// WP7 — `spoken: false` asks for a text-only reply (the chat thread);
    /// sending while Halo is thinking or talking interrupts that turn.
    func sendText(_ message: String, spoken: Bool = true) async {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Phase 12 — quick-action buttons hand us a prompt before
        // connection_ack lands. Queue it so it sends the moment
        // we're ready instead of silently dropping. Flushed by the
        // connection_ack handler.
        if state == .connecting {
            pendingInitialMessage = message
            pendingInitialSpoken = spoken
            return
        }

        switch state {
        case .idle, .listening:
            break
        case .processing, .speaking:
            // Interrupt the reply in flight: cancel server-side, drop
            // any audio still arriving for it.
            cancelCurrentTurn()
            streamingAudioPlayer?.stopAndDiscardPending()
            isPlayingAcknowledgment = false
            audioFeedback.stopProcessingPulse()
        default:
            return
        }

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
        // Kick off the thinking-pulse feedback (haptic + soft tone
        // every 3s) so the user knows the agent is working. Stops
        // when the first audio chunk lands.
        audioFeedback.feedbackForStateChange(.processing)
        await sendTextInternal(message, spoken: spoken)
    }

    private var pendingInitialSpoken: Bool = true

    /// WP7 — cancel the turn in flight (barge-in, Stop, a new message).
    /// The server answers with turn_cancelled; anything still arriving
    /// for this id is dropped by handleAgentEvent.
    func cancelCurrentTurn(notifyPlaybackFinished: Bool = true) {
        if workflowActivity?.isWorking == true { workflowActivity = workflowActivity?.interrupted() }
        if finalizationID != nil {
            cancelSpeechFinalization()
            isVoiceSessionActive = false
            sttService.disconnect()
            transcriptStore?.discardDraft()
            capturedBuffers = []
        }
        voiceTiming.reset()
        guard let turnId = currentTurnId else { return }
        cancelledTurnIds.append(turnId)
        if cancelledTurnIds.count > 20 { cancelledTurnIds.removeFirst(cancelledTurnIds.count - 20) }
        currentTurnId = nil
        streamingAudioPlayer?.stopAndDiscardPending(notify: notifyPlaybackFinished)
        Task { [weak self] in
            guard let self else { return }
            try? await self.agentWebSocket.sendCancel(turnId: turnId)
        }
    }

    private func isStaleTurn(_ turnId: String?) -> Bool {
        guard let turnId else { return false }
        if cancelledTurnIds.contains(turnId) { return true }
        if let current = currentTurnId, current != turnId { return true }
        return false
    }

    /// Internal: Send text to agent (used by both text input and voice finalization)
    private func sendTextInternal(_ message: String, spoken: Bool = true,
                                  turnEndedAt: TimeInterval? = nil, lastSpeechAt: TimeInterval? = nil) async {
        let lifecycle = lifecycleID
        do {
            currentAgentResponseId = UUID()
            let turnId = UUID().uuidString
            workflowActivity = nil
            currentTurnId = turnId
            voiceTiming.reset()
            if spoken {
                voiceTiming.begin(turnId: turnId, sentAt: ProcessInfo.processInfo.systemUptime,
                                  endedAt: turnEndedAt, lastSpeechAt: lastSpeechAt)
            }

            // We're starting a fresh turn — re-open the audio player's
            // chunk gate. If the previous turn ended via barge-in, the
            // gate was closed to drop late server-streamed chunks for
            // the abandoned response. Now that we're requesting a new
            // response, audio chunks arriving from here on are for the
            // current turn and should be accepted.
            streamingAudioPlayer?.resumeAcceptingChunks()

            let context: [String: AnyCodable] = [
                "platform": AnyCodable("ios"),
                "supports_app_actions": AnyCodable(true),
                "app_action_destinations": AnyCodable(["money", "budget", "benefits", "settings", "accounts", "transactions", "calendar", "income", "bills", "investments", "attention"]),
                "conversation_thread_id": AnyCodable(transcriptStore?.currentSessionId.uuidString ?? ""),
                "sessionId": AnyCodable(sessionId ?? ""),
                "timestamp": AnyCodable(Date().timeIntervalSince1970),
                "timezone": AnyCodable(TimeZone.current.identifier),
            ]

            try await agentWebSocket.sendMessage(
                message, context: context, turnId: turnId,
                streamAudio: spoken, streamText: !spoken
            )

            // Processing feedback already began with the state transition.
            // A delayed second cue could fire after playback or after closing.
        } catch {
            guard lifecycleID == lifecycle, !Task.isCancelled else { return }
            setState(.error(error.localizedDescription))
        }
    }

    /// Set muted state (only affects TTS/sounds, not voice recording)
    func setMuted(_ muted: Bool) {
        isMuted = muted

        // Propagate to streaming audio player
        streamingAudioPlayer?.setMuted(muted)

        // Speaker mute changes output volume only. The reply still completes;
        // explicit interruption is a separate action.
    }

    /// Hands-free mic mute. Doesn't tear down STT — the WebSocket
    /// stays open and audio continues to flow from VoiceService;
    /// `setupSTTCallbacks` checks `isMicMuted` before forwarding any
    /// frames. Cheap toggle so users can pause for side conversations
    /// without re-fetching an STT token on every unmute.
    func setMicMuted(_ muted: Bool) {
        let wasMuted = isMicMuted
        isMicMuted = muted
        if muted { interruptionAudio.reset(); bargeInDetector.reset() }
        // On unmute, reset the silence-detection clock so the previous
        // silence accumulated while muted doesn't immediately auto-commit
        // an empty turn the moment the mic is live again. We also clear
        // hasDetectedSpeechInCurrentListen so the user has to actually
        // speak (not just unmute into ambient silence) before silence
        // can trigger a commit.
        if wasMuted && !muted {
            lastVoiceActivityAt = nil
            hasDetectedSpeechInCurrentListen = false
            listenStartedAt = Date()
            if state == .idle && agentWebSocket.isConnected {
                Task { await self.startListening() }
            }
        }
    }

    /// Update the active conversation mode. Called by the view model
    /// after reading @AppStorage; idempotent.
    func setConversationMode(_ mode: ConversationMode) {
        conversationMode = mode
    }

    /// Hands-free explicit end. Equivalent to `disconnect()` but
    /// expresses intent — used by the End Conversation button so the
    /// call site reads cleanly. Push-to-talk users can still call
    /// `disconnect()` directly.
    func endConversation() {
        disconnect()
    }

    /// Stop current TTS without affecting mute state (skip this message)
    func stopSpeaking() {
        Diagnostics.send("voice_barge_in", ["source": "button"])
        bargeIn(preserveOpeningAudio: false)
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

        // SINGLE CHOKE POINT for continuous haptics. Reconcile the looping
        // pulse to the new state on EVERY transition — this is what
        // guarantees the "thinking"/"listening" buzz can't outlive the
        // conversation. Any exit (disconnect, end, speaking, error, idle)
        // maps to nil below and stops the loop; the engine's safety lease
        // is the backstop if a transition is ever missed entirely.
        Haptics.engine.setContinuous(Self.continuousHaptic(for: newState))

        // Legacy AUDIBLE thinking-pulse (sound loop, no longer a haptic) —
        // stop it whenever we leave .processing.
        if oldState == .processing && newState != .processing {
            audioFeedback.stopProcessingPulse()
        }

        // Announce state change for accessibility (throttled)
        if oldState != newState {
            announceStateChange(newState)
        }
    }

    /// Map a conversation state to its continuous haptic (nil = none).
    /// A single ready cue marks listening; continuous feedback is only for waits.
    /// Overlapping a listening loop with the ready cue made the cue ambiguous.
    private static func continuousHaptic(for state: ConversationState) -> HapticPattern? {
        switch state {
        case .processing, .connecting: return .pulseThinking
        default: return nil
        }
    }

    private func emitEvent(_ event: ConversationEvent) {
        onEvent?(event)
    }

    /// WP5 — the server names what changed; the stores invalidate by scope.
    /// Replaces the old "any agent reply → refresh" heuristic.
    private func handleDataMutated(_ payload: DataMutatedPayload) {
        let info: [String: Any] = ["scope": payload.scope]
        NotificationCenter.default.post(name: .budgetDataDidMutate, object: nil, userInfo: info)
        if payload.scope == "accounts" {
            NotificationCenter.default.post(name: .bankDataDidMutate, object: nil, userInfo: info)
        }
    }

    private func handleSpeakingFinished() {
        Logger.debug("ConversationCoordinator: handleSpeakingFinished state=\(state) mode=\(conversationMode.rawValue) muted=\(isMicMuted) ack=\(isPlayingAcknowledgment)")

        // The player stopped because the session ended (X, Stop, phone
        // call) or the socket is gone: settle to idle, never restart the mic.
        if suppressNextAutoResume || sessionId == nil || !agentWebSocket.isConnected {
            suppressNextAutoResume = false
            isPlayingAcknowledgment = false
            bargeInRequested = false
            if state == .speaking || state == .connecting { setState(.idle) }
            return
        }

        // Mark the TTS-end timestamp so startListening can decide
        // whether the pre-roll ring is fresh enough to flush (Halo's
        // voice may have bled into it within the last couple seconds)
        // or safe to keep (Halo finished long enough ago that the
        // ring has cycled past her voice and contains only ambient).
        lastSpeakingEndedAt = Date()
        // A full Halo reply just played — real conversation activity.
        markMeaningfulActivity()

        // The ack audio just finished — but the real agent response
        // is still on the way. Hold state in .processing so the
        // input button doesn't flicker to "Tap to talk".
        if isPlayingAcknowledgment {
            isPlayingAcknowledgment = false
            // Only when the ack ended on its own while we were still
            // speaking. A barge-in or Stop during the ack must fall through
            // to the auto-resume below, or hands-free strands in .processing.
            if state == .speaking && !bargeInRequested {
                setState(.processing)
                // Resume the thinking-pulse — the audio_chunk
                // handler stopped it when the ack chunks landed,
                // and now we're back to genuine waiting until
                // the response chunks start arriving.
                audioFeedback.feedbackForStateChange(.processing)
                return
            }
        }

        // In hands-free, the playback-finished signal is deterministic:
        // Halo stopped talking, mic should resume. We previously gated
        // this on state == .speaking || .connecting, but agentResponse
        // events can transiently flip state to .idle between audio
        // chunks (when the response arrives before the first audioChunk),
        // causing silent fall-through and the user has to tap the
        // button to wake the mic. Trust the playback signal instead.
        // Pattern-match exclusions (state is non-Hashable due to
        // .error(String); use a switch to test).
        let canAutoResume: Bool = {
            switch state {
            case .listening, .disconnected, .permissionNeeded, .error:
                return false
            default:
                return true
            }
        }()
        if conversationMode == .handsFree && !isMicMuted && canAutoResume {
            bargeInRequested = false
            // A terminal frame can arrive between audio buffers while state is
            // processing. startListening accepts idle/speaking, not processing.
            if state == .processing { setState(.idle) }
            resumeListeningTask?.cancel()
            let lifecycle = lifecycleID
            resumeListeningTask = Task { [weak self] in
                guard let self, self.lifecycleID == lifecycle, !Task.isCancelled else { return }
                await self.startListening()
            }
            return
        }

        // Push-to-talk path (or hands-free with mute / unrecoverable
        // state): just settle to idle so the user can tap to talk.
        if state == .speaking || state == .connecting || state == .processing {
            setState(.idle)
        }
    }

    // MARK: - Agent Event Handling

    /// Handles all events from the AgentWebSocketManager event stream.
    /// Replaces the previous 7 separate callback closures with a single sequential handler.
    func handleAgentEvent(_ event: AgentEvent) {
        // WP7 — anything for a cancelled or superseded turn is dropped
        // before it can touch the player or the transcript.
        // turn_cancelled is the server confirming OUR cancel, so it carries
        // the cancelled id and must be handled before the stale filter.
        if case .turnCancelled(let payload) = event {
            audioFeedback.stopProcessingPulse()
            isPlayingAcknowledgment = false
            // Only settle if nothing newer replaced the turn.
            if state == .processing, currentTurnId == nil || currentTurnId == payload.turnId {
                currentTurnId = nil
                setState(.idle)
                if conversationMode == .handsFree && !isMicMuted && isConnected {
                    let lifecycle = lifecycleID
                    resumeListeningTask?.cancel()
                    resumeListeningTask = Task { [weak self] in
                        guard let self, self.lifecycleID == lifecycle, !Task.isCancelled else { return }
                        await self.startListening()
                    }
                }
            }
            return
        }
        if isStaleTurn(event.turnId) {
            Logger.debug("ConversationCoordinator: dropping stale event for turn \(event.turnId ?? "?")")
            return
        }
        switch event {
        case .turnCancelled:
            break

        case .connectionAck(let ack):
            warmSpeechRecognition()
            if let started = connectionStartedAt {
                Diagnostics.send("voice_connection_ready", ["connect_ms": String(Int((ProcessInfo.processInfo.systemUptime - started) * 1000)),
                    "backend_pipeline": ack.pipelineRevision ?? "legacy"])
            }
            if let serverSessionId = ack.sessionId ?? ack.connectionId {
                sessionId = serverSessionId
            }
            // Default behavior: stay in .connecting until the first
            // agent message arrives (the welcome/intro). The button
            // shows "Connecting..." while the intro loads.
            //
            // Phase 12 — when the caller asked us to skip the
            // greeting, no intro will ever arrive. Transition to
            // .idle now so queued prompts can send and the input
            // surface unlocks.
            if skipGreetingForCurrentConnection {
                setState(.idle)
            }

            // Flush any prompt queued by sendText while we were
            // still in .connecting. This is the path quick-action
            // buttons take.
            if let pending = pendingInitialMessage {
                pendingInitialMessage = nil
                let spoken = pendingInitialSpoken
                pendingInitialSpoken = true
                let lifecycle = lifecycleID
                Task { [weak self] in
                    guard let self, self.lifecycleID == lifecycle, !Task.isCancelled else { return }
                    await self.sendText(pending, spoken: spoken)
                }
            }

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
            // WP7 — never touch state while the mic is live.
            if state != .listening,
               streamingAudioPlayer?.isPlaying != true && streamingAudioPlayer?.isBuffering != true {
                setState(.idle)
            }
            currentAgentResponseId = nil
            backfillRecordingAgentResponse(response.message)

        case .audioChunk(let chunk):
            audioFeedback.stopProcessingPulse()
            Logger.debug("ConversationCoordinator: Audio chunk received, player=\(streamingAudioPlayer != nil), isPlaying=\(streamingAudioPlayer?.isPlaying ?? false)")
            streamingAudioPlayer?.appendAudioChunk(chunk.audio)

        case .audioComplete(let complete):
            if event.turnId == nil, !complete.isAck,
               (complete.data?["is_error"]?.value as? Bool) != true,
               interactionMode == .voice, conversationMode == .handsFree,
               !sttService.isSessionReady, !greetingPlaybackRecorded {
                let lifecycle = lifecycleID
                resumeListeningTask?.cancel()
                resumeListeningTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.connectWithTimeout()
                        guard self.lifecycleID == lifecycle, !Task.isCancelled else { return }
                        self.handleAgentEvent(event)
                    } catch {
                        guard self.lifecycleID == lifecycle, !Task.isCancelled else { return }
                        self.streamingAudioPlayer?.stopAndDiscardPending(notify: false)
                        self.handleVoiceSetupError(error)
                    }
                }
                return
            }
            // Backend now emits intermediate audio_complete events on
            // every sentence boundary (data.is_partial == true) so the
            // client plays each sentence as it lands instead of waiting
            // for the full response to finish synthesizing. The final
            // event of the turn omits is_partial (or sets it to false)
            // and carries the full message body.
            let isAck = complete.isAck
            let body = complete.responseText
            let isPartial: Bool = {
                guard let data = complete.data,
                      let raw = data["is_partial"]?.value else { return false }
                return (raw as? Bool) ?? false
            }()
            Logger.debug("ConversationCoordinator: audio_complete isAck=\(isAck), isPartial=\(isPartial), bodyLen=\(body.count), state=\(state)")

            // Response audio (partial or final) means the ack is over, even
            // if its buffer is still draining: the player runs straight
            // into the queued response without a "finished" callback.
            if !isAck { isPlayingAcknowledgment = false }

            // Only emit the final transcript on the LAST audio_complete.
            // Intermediate events have an empty body anyway, but this
            // double-check keeps the contract clean.
            if !isPartial {
                if isAck {
                    isPlayingAcknowledgment = true
                } else if !body.isEmpty {
                    let responseId = currentAgentResponseId ?? UUID()
                    emitEvent(.agentFinal(body, id: responseId))
                    currentAgentResponseId = nil
                    backfillRecordingAgentResponse(body)
                }
            }
            // Voice-speed override may arrive on any audio_complete; honor it.
            if let data = complete.data,
               let speedValue = (data["voice_speed"]?.value as? Double) ?? (data["voice_speed"]?.value as? Int).map(Double.init) {
                streamingAudioPlayer?.playbackRate = Float(speedValue)
            }
            playAccumulatedAudio(isFinal: !isPartial, turnId: event.turnId, isAcknowledgment: isAck,
                                 isError: (complete.data?["is_error"]?.value as? Bool) == true)

        case .error(let error):
            if workflowActivity?.isWorking == true { workflowActivity = workflowActivity?.interrupted() }
            if error.code == "AUDIO_DELIVERY_FAILED" {
                handleAudioDeliveryFailure(error.error)
                return
            }
            audioFeedback.stopProcessingPulse()
            setState(.error(error.error))
            audioFeedback.feedbackForStateChange(.error(error.error))

            if AgentWebSocketManager.terminalErrorCodes.contains(error.code) {
                listenTask?.cancel()
                listenTask = nil
                resumeListeningTask?.cancel()
                resumeListeningTask = nil
                sttWarmupTask?.cancel()
                sttWarmupTask = nil
                prewarmTask?.cancel()
                prewarmTask = nil
                idleWatchdogTask?.cancel()
                idleWatchdogTask = nil
                sttService.onSessionReady = nil
                cancelSpeechFinalization()
                isVoiceSessionActive = false
                suppressNextAutoResume = true
                voiceService.stopRecording()
                voiceService.onAudioBuffer = nil
                sttService.disconnect()
                transcriptStore?.discardDraft()
                streamingAudioPlayer?.stopAndDiscardPending()
                UIAccessibility.post(notification: .announcement, argument: error.error)
                return
            }

            // Hands-free: an agent error (including guardrail rejections,
            // which arrive as plain error events with no TTS) used to
            // strand the loop in .error forever — dead air with minutes
            // metering. Announce and auto-recover to listening, mirroring
            // the STT-error recovery path.
            if conversationMode == .handsFree && !isMicMuted {
                let lifecycle = lifecycleID
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard !Task.isCancelled, let self, self.lifecycleID == lifecycle, self.state == .error(error.error),
                          self.agentWebSocket.isConnected else { return }
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "I couldn't process that. I'm listening again."
                    )
                    self.setState(.idle)
                    await self.startListening()
                }
            }

        case .acknowledgment(let ack):
            Logger.info("ConversationCoordinator: Agent acknowledged, thinking...")
            if let text = ack.text, !text.isEmpty {
                emitEvent(.status(text))
            }

        case .voiceStatus:
            // Voice-status path was removed — the AccountsAgent's
            // contextual `acknowledgment` event covers the same purpose
            // with better wording. We still decode the payload at the
            // network layer (so a pre-rollback backend doesn't crash
            // the app) but we deliberately drop it here.
            break

        case .reconnecting:
            if workflowActivity?.isWorking == true { workflowActivity = workflowActivity?.interrupted() }
            resumeListeningTask?.cancel(); resumeListeningTask = nil
            sttRecoveryTask?.cancel(); sttRecoveryTask = nil
            cancelSpeechFinalization()
            isVoiceSessionActive = false
            isPlayingAcknowledgment = false
            currentAgentResponseId = nil
            transcriptStore?.discardDraft()
            currentTurnId = nil
            audioFeedback.stopProcessingPulse()
            streamingAudioPlayer?.stopAndDiscardPending(notify: false)
            voiceService.onAudioBuffer = nil
            voiceService.stopRecording()
            sttService.disconnect()
            listenTask?.cancel(); listenTask = nil
            sttWarmupTask?.cancel(); sttWarmupTask = nil
            setState(.connecting)
        case .sessionResumed:
            streamingAudioPlayer?.resumeAcceptingChunks()
            setState(.idle)
            let lifecycle = lifecycleID
            resumeListeningTask?.cancel()
            resumeListeningTask = Task { [weak self] in
                guard let self, self.lifecycleID == lifecycle, !self.isMicMuted else { return }
                await self.startListening()
            }
        case .permanentDisconnect:
            setState(.disconnected)
            emitEvent(.errorEvent("Connection lost. Please go back and try again."))

        case .workflowActivity(let payload):
            guard let activeTurn = currentTurnId, payload.turnId == activeTurn, payload.isSupported else { return }
            workflowActivity = payload

        case .appAction(let payload):
            guard payload.action.kind == "navigate", payload.action.state == "proposed" else { return }
            setState(.idle)
            NotificationCenter.default.post(name: VoiceNavigation.requested, object: payload.action.target)
        case .dataMutated(let payload):
            handleDataMutated(payload)
        }
    }

    // MARK: - STT Callbacks (ElevenLabs)

    private func setupSTTCallbacks() {
        // Handle transcription updates (partial and committed)
        sttService.onConfiguration = { [weak self] config in
            guard let self else { return }
            if let mode = config.conversationMode {
                self.setConversationMode(ConversationMode.from(mode))
                UserDefaults.standard.set(self.conversationMode.rawValue, forKey: "conversationMode")
            }
            if let ms = config.minSpeechMs {
                self.minSpeechDuration = min(1.0, max(0.1, Double(ms) / 1000))
            }
        }
        sttService.onTranscription = { [weak self] text, isFinal in
            guard let self = self else { return }

            // Only an active input turn owns transcripts. During playback we
            // detect speech locally and replay its opening audio after stopping
            // Halo, so delayed output/keepalive transcripts cannot trigger turns.
            guard self.isVoiceSessionActive else { return }

            // Short answers such as "no" must reach confirmation logic.
            if isFinal {
                // Server committed a segment. Fold it into the accumulated
                // draft — the next partial carries ONLY the new segment's
                // words, so this must never clear what came before.
                self.lastServerCommitAt = Date()
                self.transcriptStore?.commitSegment(text)

                // A mid-speech commit is a SEGMENT BOUNDARY, not end of
                // turn. Only hands-free auto-sends (its silence detection
                // + server VAD agree the user stopped); in push-to-talk
                // the user's finger ends the turn — auto-sending here
                // would fire mid-monologue at every ~20-25s rollover.
                if self.conversationMode == .handsFree,
                   self.lastVoiceActivityAt.map({ Date().timeIntervalSince($0) >= 0.3 }) ?? true {
                    self.stopListeningAndProcess(serverCommitted: true)
                }
            } else {
                // Partial: replaces only the current segment's text so it's
                // available for finalization, even if state has already
                // moved to .processing (user tapped stop, commit flushing).
                self.transcriptStore?.updateDraft(text)
            }
        }

        sttService.onError = { [weak self] error in
            self?.handleRecognitionFailure(error)
        }
        sttService.onDisconnected = { [weak self] in
            guard let self, self.isVoiceSessionActive, self.state == .listening else { return }
            self.handleRecognitionFailure(URLError(.networkConnectionLost))
        }
    }

    private func handleRecognitionFailure(_ error: Error, allowOutputToContinue: Bool = true,
                                          messageOverride: String? = nil) {
        let canRecover = conversationMode == .handsFree && !isMicMuted &&
            sessionId != nil && agentWebSocket.isConnected
        let preserveCapture = allowOutputToContinue && canRecover && finalizationID == nil &&
            (state == .speaking || state == .processing)
        let quotaError: Bool = {
            guard let error = error as? ElevenLabsSTTError else { return false }
            if case .resourceExhausted = error { return true }
            return false
        }()
        let willRetry = canRecover && !quotaError && sttRecoveryAttempts < 1
        let recoveryMessage = messageOverride ?? Self.friendlySTTError(error)
        let phase = state == .speaking ? "speaking" : (state == .processing ? "processing" : "listening")
        Diagnostics.send("voice_stt_failure", ["phase": phase, "preserved_capture": preserveCapture ? "1" : "0"])
        Logger.error("STT failure: \(error.localizedDescription)")
        cancelSpeechFinalization()
        interruptionAudio.reset()
        isVoiceSessionActive = false
        transcriptStore?.discardDraft()
        capturedBuffers = []
        if !preserveCapture {
            lastAnnouncementTime = Date()
            voiceService.stopRecording()
            voiceService.onAudioBuffer = nil
            // A displayed input error must never leave old output playing over it.
            cancelCurrentTurn()
            streamingAudioPlayer?.stopAndDiscardPending()
            resumeListeningTask?.cancel()
            resumeListeningTask = nil
            lastAnnouncementTime = Date() // One explicit announcement, not two.
            setState(.error(recoveryMessage))
            if !willRetry { UIAccessibility.post(notification: .announcement, argument: recoveryMessage) }
        }
        // While output continues, retain the mic for local interruption detection.
        // One automatic recovery per successfully submitted turn prevents loops.
        guard willRetry else { return }
        sttRecoveryAttempts += 1
        let lifecycle = lifecycleID
        sttRecoveryTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.lifecycleID == lifecycle, !Task.isCancelled,
                  self.sessionId != nil, self.agentWebSocket.isConnected, !self.isMicMuted else { return }
            if preserveCapture {
                do { try await self.sttService.connect() }
                catch { Diagnostics.send("voice_stt_recovery_failed") }
            } else if self.state == .error(recoveryMessage) {
                // VoiceOver must finish the error before capture restarts;
                // otherwise its own words can become the next user request.
                guard await self.announceBeforeRecognitionRecovery(recoveryMessage),
                      self.lifecycleID == lifecycle, !Task.isCancelled,
                      self.state == .error(recoveryMessage), !self.isMicMuted else { return }
                self.lastAnnouncementTime = Date()
                self.setState(.idle)
                await self.startListening()
            }
        }
    }

    private func announceBeforeRecognitionRecovery(_ message: String) async -> Bool {
        guard UIAccessibility.isVoiceOverRunning else { return true }
        let gate = TranscriptCommitGate()
        let observer = NotificationCenter.default.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main
        ) { notification in
            guard notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String == message else { return }
            Task { @MainActor in gate.complete() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        return await gate.wait(timeout: 8) {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func handleAgentResponseComplete(id: UUID) {
        // WP7 — text completion never flips to .speaking; the player's
        // onPlaybackStarted does, once a buffer is actually playing.
        if isPrivacyMode, state != .listening {
            setState(.idle)
        }
    }

    private func playAccumulatedAudio(isFinal: Bool = true, turnId: String? = nil, isAcknowledgment: Bool = false, isError: Bool = false) {
        guard !isPrivacyMode else {
            Logger.info("ConversationCoordinator: Skipping audio for privacy mode")
            setState(.idle)
            return
        }

        // WP7 — .speaking is set by onPlaybackStarted after the player
        // accepts the buffer, not here.
        streamingAudioPlayer?.playAccumulatedAudio(isFinal: isFinal, turnId: turnId, isAcknowledgment: isAcknowledgment, isError: isError)
    }

    // MARK: - Accessibility Announcements

    private var lastAnnouncementTime: Date = .distantPast
    private let announcementDebounceInterval: TimeInterval = 0.8

    private func announceStateChange(_ state: ConversationState) {
        // Suppress VoiceOver state announcements while the mic is hot
        // OR while Halo is actively speaking. Real-device tests caught
        // VoiceOver speaking the announcement THROUGH the device
        // speaker, the mic picking it up, and the next STT turn
        // including VoiceOver's voice as user-said. Halo's own audio
        // already covers the audible-feedback channel for these
        // states; the haptic patterns from HapticEngine cover the
        // tactile channel. VoiceOver here is double-coverage that
        // creates a feedback loop.
        switch state {
        case .listening, .processing, .speaking, .connecting:
            return
        default:
            break
        }

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

        // Audio-session interruptions (phone call, Siri, alarm). Without
        // this, an incoming call deactivates the session and the
        // conversation dies in silent .idle with no way to recover (F045).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        // Route changes: iOS can silently revert the output to the quiet
        // earpiece (category churn, override cleared by the system). The
        // speaker override was previously re-applied only at
        // playback-sequence start, so a mid-session reversion stuck for
        // the rest of the turn — "Halo suddenly way quieter at max volume".
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func appWillResignActive() {
        pauseAudioAndReturnToIdle(announcement: "Conversation paused")
    }

    @objc private func appDidBecomeActive() {
        // Could auto-reconnect here if needed
    }

    /// Handle an audio-session interruption (phone call, Siri, alarm, another
    /// app taking the session). On `.began` the OS has already deactivated our
    /// session, so tear down cleanly and tell the user; on `.ended` let them
    /// know they can continue (the next tap re-activates the session). We do
    /// NOT auto-restart the mic — resuming is user-initiated (F045).
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            pauseAudioAndReturnToIdle(announcement: "Conversation paused")
        case .ended:
            // Re-apply the session config + speaker override NOW: iOS can
            // reactivate the session routed to the earpiece, and nothing
            // else re-applies the override until the next playback sequence
            // — the first response after a Siri/call/alarm interruption
            // played "way too quiet even at max volume".
            do {
                try StreamingAudioPlayer.configureSharedSession()
            } catch {
                Logger.error("Failed to reconfigure audio session after interruption: \(error)")
            }
            let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            if shouldResume {
                UIAccessibility.post(notification: .announcement, argument: "Ready. Tap to continue.")
            }
        @unknown default:
            break
        }
    }

    /// Re-assert the loud-speaker route when the system clears our override.
    /// Only for reasons that indicate a config/override change — plugging in
    /// headphones (.newDeviceAvailable) must NOT be fought. Unplugging them
    /// (.oldDeviceUnavailable) and system reconfiguration
    /// (.routeConfigurationChange) both land on the quiet earpiece unless
    /// the override is re-applied, which is the "Halo went quiet after I
    /// took my headphones off" report.
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else { return }

        switch reason {
        case .categoryChange, .override, .oldDeviceUnavailable, .routeConfigurationChange:
            let session = AVAudioSession.sharedInstance()
            let isReceiver = session.currentRoute.outputs.contains {
                $0.portType == .builtInReceiver
            }
            if isReceiver {
                Logger.warning("Audio route reverted to receiver — re-forcing speaker")
                StreamingAudioPlayer.forceSpeakerIfNoHeadphones(session: session)
            }
        default:
            break
        }
    }

    /// Tear down live audio (mic + STT + playback) and return to idle,
    /// announcing why. Shared by app-backgrounding and audio-session
    /// interruptions so a blind user always HEARS what happened instead of
    /// dropping into a silent idle state (F045 / V4).
    private func pauseAudioAndReturnToIdle(announcement: String) {
        sttRecoveryTask?.cancel()
        sttRecoveryTask = nil
        listenTask?.cancel()
        listenTask = nil
        resumeListeningTask?.cancel()
        resumeListeningTask = nil
        sttWarmupTask?.cancel()
        sttWarmupTask = nil
        prewarmTask?.cancel()
        prewarmTask = nil
        sttService.disconnect()
        if state == .listening {
            voiceService.stopRecording()
            voiceService.onAudioBuffer = nil
            sttService.disconnect()
            isVoiceSessionActive = false
            transcriptStore?.discardDraft()
        }

        if state == .speaking {
            // We do NOT auto-restart the mic after an interruption.
            suppressNextAutoResume = true
            cancelCurrentTurn()
            streamingAudioPlayer?.stop()
        }

        if state != .idle && state != .disconnected {
            emitEvent(.status("Paused"))
            // Bump the throttle timestamp so the generic .idle state
            // announcement is suppressed and our specific message is the
            // one the user hears (no double-speak).
            lastAnnouncementTime = Date()
            setState(.idle)
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
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
