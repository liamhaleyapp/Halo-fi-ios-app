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
import AVFoundation

@Observable
@MainActor
final class ConversationCoordinator {
    // MARK: - Singleton

    static let shared = ConversationCoordinator()

    // MARK: - Public State (Read-Only)

    private(set) var state: ConversationState = .idle
    private(set) var sessionId: String?
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
    private(set) var conversationMode: ConversationMode = .pushToTalk

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
    private var prewarmTask: Task<Void, Never>?
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
    private let silenceCommitInterval: TimeInterval = 0.5

    // MARK: - Hands-free barge-in
    //
    // When the user starts talking while Halo is mid-response, we
    // immediately stop the TTS playback and switch to listening —
    // VoIP-style interruption. Implementation: keep voiceService
    // recording across all hands-free states (not just .listening),
    // route buffers to a barge-in detector during .speaking, and
    // call streamingAudioPlayer.stop() the moment we see sustained
    // voice activity above bargeInThreshold.

    /// Linear RMS that must be exceeded to count as a barge-in
    /// candidate buffer. Initially set to 0.10 (well above any AEC
    /// bleed) but in practice .voiceChat AEC also slightly
    /// attenuates the user's voice when both Halo and user are
    /// speaking, so legitimate barge-in attempts often landed at
    /// 0.04–0.06. Matching voiceActivityRMSThreshold is safe given
    /// AEC's residual bleed sits below this floor.
    private let bargeInRMSThreshold: Float = 0.04

    /// Number of consecutive above-threshold buffers required
    /// before we trust the signal. Buffers arrive at roughly 50fps
    /// so 3 frames ≈ 60ms — enough to dodge a single-buffer spike
    /// from a click / pop / breath without making the user feel
    /// like they need to project to interrupt.
    private let bargeInRequiredFrames: Int = 3
    private var bargeInConsecutiveFrames: Int = 0

    /// Set by `bargeIn()` immediately before stopping the player so
    /// `handleSpeakingFinished` can skip its 400ms settling delay —
    /// a barge-in needs to flip to listening instantly.
    private var bargeInRequested: Bool = false

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
    /// 12s comfortably covers a multi-sentence question; users rarely
    /// monologue longer than that without pausing.
    private let maxListenDuration: TimeInterval = 12.0

    /// Hands-free safety net — if the user opens the conversation,
    /// hears the greeting, but never speaks, auto-commit anyway after
    /// this long so we don't burn the STT session forever.
    private let maxListenWithoutSpeech: TimeInterval = 30.0

    /// When the current listening turn started — used by the safety
    /// timeout above. Cleared by stopListeningAndProcess.
    private var listenStartedAt: Date?

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

        // Sync the player's audio session config to the current
        // conversation mode immediately. setConversationMode also keeps
        // this in sync on subsequent toggles.
        streamingAudioPlayer.needsAECDuringPlayback = (conversationMode == .handsFree)

        streamingAudioPlayer.onPlaybackFinished = { [weak self] in
            Task { @MainActor in
                self?.handleSpeakingFinished()
            }
        }
    }

    // MARK: - Public API

    /// Connect to the backend.
    ///
    /// Phase 12 — pass ``skipGreeting: true`` when a quick-action
    /// flow is about to send a pre-prompt; the backend will skip
    /// its initial greeting so the user hears the answer to their
    /// tap, not a "Good evening" speech first.
    func connect(skipGreeting: Bool = false) async {
        guard state == .idle || state == .disconnected else { return }

        // Phase 12 — store the flag so connection_ack handling can
        // transition straight to .idle (otherwise state stays in
        // .connecting forever waiting for an intro message that
        // will never arrive, and queued prompts silently drop).
        self.skipGreetingForCurrentConnection = skipGreeting

        setState(.connecting)
        sessionId = UUID().uuidString

        do {
            try await agentWebSocket.connect(skipGreeting: skipGreeting)

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
            //
            // In hands-free we go further and START RECORDING right
            // after pre-warm, plus wire the buffer router. That makes
            // barge-in work even during the welcome message — without
            // this, the mic is dormant until the first turn ends.
            prewarmTask?.cancel()
            prewarmTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.voiceService.preWarmCapture()

                    if self.conversationMode == .handsFree {
                        // Wire the same router we use during a normal
                        // listen turn. Once startListening fires for
                        // the first real turn it'll re-wire with a
                        // fresh closure — no duplicate calls.
                        self.voiceService.onAudioBuffer = { [weak self] buffer in
                            guard let self = self else { return }
                            if self.isMicMuted { return }
                            Task { @MainActor [weak self] in
                                self?.routeAudioBuffer(buffer)
                            }
                        }
                        try await self.voiceService.startRecording()
                        Logger.info("Hands-free: voice service primed for barge-in during welcome")
                    }
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
        bargeInConsecutiveFrames = 0
        bargeInRequested = false
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
                        // Wire audio buffers — single closure that routes
                        // every frame based on the current conversation
                        // state. Hands-free keeps voiceService recording
                        // across listen / process / speak so we can detect
                        // barge-in (user interrupting Halo mid-response).
                        self.voiceService.onAudioBuffer = { [weak self] buffer in
                            guard let self = self else { return }
                            if self.isMicMuted { return }
                            Task { @MainActor [weak self] in
                                self?.routeAudioBuffer(buffer)
                            }
                        }

                        // Reset silence-detection state for this turn so
                        // residual values from a prior listen can't trigger
                        // a phantom commit on the new one.
                        self.hasDetectedSpeechInCurrentListen = false
                        self.lastVoiceActivityAt = nil
                        self.listenStartedAt = Date()

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
            try await connectWithTimeout()

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

    /// Stop listening (voice mode) - finalize and send transcript.
    /// Called when the user explicitly ends their turn (PTT button
    /// release or manual stop in hands-free). Backend serves
    /// commit_strategy="vad" for both modes, so server-side VAD has
    /// already committed by this point and a plain disconnect is
    /// safe — no need for the explicit commit + 2s flush wait.
    func stopListening() {
        guard state == .listening else { return }

        // Play stop listening feedback immediately
        audioFeedback.feedbackForStateChange(.idle)

        // Mark session inactive BEFORE disconnect to prevent "unexpected disconnect" warning
        isVoiceSessionActive = false

        // Reset silence detection so the next listen starts clean.
        hasDetectedSpeechInCurrentListen = false
        lastVoiceActivityAt = nil
        listenStartedAt = nil

        // Stop recording and STT
        voiceService.stopRecording()
        voiceService.onAudioBuffer = nil
        sttService.disconnect()

        // Finalize draft and send to agent
        if let finalText = transcriptStore?.finalizeDraft(), !finalText.trimmingCharacters(in: .whitespaces).isEmpty {
            setState(.processing)
            // Kick off the thinking-pulse haptic + sound so the user
            // knows Halo is working. Mirrors the public sendText path.
            audioFeedback.feedbackForStateChange(.processing)

            Task {
                await sendTextInternal(finalText)
            }
        } else {
            setState(.idle)
        }
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
            // Send to STT, tap silence detection, AND accumulate the
            // raw buffer for post-turn training-data upload. The
            // upload itself runs background-detached after the turn
            // is committed — appending here is the cheap part.
            Task { await sttService.sendAudioBuffer(buffer) }
            processAudioBufferForSilenceDetection(buffer)
            capturedBuffers.append(buffer)

        case .speaking:
            // Hands-free only: watch for the user starting to talk
            // while Halo is mid-response, and interrupt if so.
            if conversationMode == .handsFree {
                processAudioBufferForBargeIn(buffer)
            }

        default:
            // .idle / .processing / .connecting / .error: ignore the
            // frame. We keep voiceService recording in hands-free so
            // the engine doesn't go through a teardown cycle between
            // turns, but there's nothing to do with the buffer here.
            break
        }
    }

    /// Look for sustained user voice during .speaking — signals the
    /// user wants to interrupt Halo's response. Requires several
    /// consecutive above-threshold frames so a single mic spike or
    /// cough doesn't silence Halo prematurely.
    private func processAudioBufferForBargeIn(_ buffer: AVAudioPCMBuffer) {
        let rms = Self.computeRMS(buffer)

        if rms < bargeInRMSThreshold {
            if bargeInConsecutiveFrames > 0 {
                Logger.debug("Barge-in: streak broken at \(bargeInConsecutiveFrames) frames (RMS=\(String(format: "%.4f", rms)))")
            }
            bargeInConsecutiveFrames = 0
            return
        }

        bargeInConsecutiveFrames += 1
        Logger.debug("Barge-in: candidate frame \(bargeInConsecutiveFrames)/\(bargeInRequiredFrames) (RMS=\(String(format: "%.4f", rms)))")
        if bargeInConsecutiveFrames >= bargeInRequiredFrames {
            bargeInConsecutiveFrames = 0
            Logger.info("Hands-free: barge-in detected (RMS=\(String(format: "%.4f", rms))) — interrupting Halo")
            bargeIn()
        }
    }

    /// Stop Halo's playback and route to listening. Triggered by
    /// barge-in detection. The actual transition to .listening flows
    /// through `handleSpeakingFinished` so we don't need to duplicate
    /// startListening's setup here.
    private func bargeIn() {
        guard state == .speaking else { return }
        bargeInRequested = true
        // stopAndDiscardPending: stop local playback AND drop any
        // chunks the server is still streaming for the abandoned
        // response. Otherwise late-arriving chunks refill the player's
        // buffer, isBuffering flips to true, and startListening's
        // bailout shoves the conversation back to .idle instead of
        // routing into a fresh listen.
        streamingAudioPlayer?.stopAndDiscardPending()
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

        // Hard cap — fires regardless of whether we detected speech.
        if let started = listenStartedAt,
           now.timeIntervalSince(started) > maxListenDuration {
            Logger.info("Hands-free: hard turn cap hit at \(String(format: "%.1f", now.timeIntervalSince(started)))s — committing")
            stopListeningAndProcess()
            return
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
    private func stopListeningAndProcess() {
        guard state == .listening else { return }

        // Play stop listening feedback immediately
        audioFeedback.feedbackForStateChange(.idle)

        // Mark session inactive BEFORE disconnect to prevent "unexpected disconnect" warning
        isVoiceSessionActive = false

        // Reset silence detection so the next listen starts clean.
        hasDetectedSpeechInCurrentListen = false
        lastVoiceActivityAt = nil
        listenStartedAt = nil
        bargeInConsecutiveFrames = 0

        // STT always disconnects between turns; we'll reconnect when
        // the next listen starts. In hands-free we keep voiceService
        // recording so the audio engine doesn't churn through a
        // teardown / re-init cycle on every turn — and so the buffer
        // router can detect barge-in during .speaking without
        // re-installing a tap. Push-to-talk keeps the original
        // teardown so the existing test surface is untouched.
        sttService.disconnect()
        if conversationMode == .pushToTalk {
            voiceService.stopRecording()
            voiceService.onAudioBuffer = nil
        }

        // Finalize draft and send to agent
        if let finalText = transcriptStore?.finalizeDraft() {
            setState(.processing)

            Task {
                await sendTextInternal(finalText)
            }

            // Snapshot + handoff for the training-data upload. We
            // copy the array so the background task owns its own
            // buffer list while we clear ours for the next turn —
            // the upload is fire-and-forget and never awaits.
            let buffersForUpload = capturedBuffers
            capturedBuffers = []
            recordingTurnNumber += 1
            let turnNumber = recordingTurnNumber
            let sessionForUpload = sessionId ?? "unknown"
            lastUploadedTurnNumber = turnNumber
            lastUserSendAt = Date()
            recordingUploader.upload(
                buffers: buffersForUpload,
                sessionId: sessionForUpload,
                turnNumber: turnNumber,
                userTranscript: finalText
            )
        } else {
            // Empty turn — drop any accumulated buffers so they
            // don't leak into the next listen.
            capturedBuffers = []
            // Empty or invalid transcript - just go idle
            setState(.idle)
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

    /// Send a text message (from text input)
    func sendText(_ message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Phase 12 — quick-action buttons hand us a prompt before
        // connection_ack lands. Queue it so it sends the moment
        // we're ready instead of silently dropping. Flushed by the
        // connection_ack handler.
        if state == .connecting {
            pendingInitialMessage = message
            return
        }

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
        // Kick off the thinking-pulse feedback (haptic + soft tone
        // every 3s) so the user knows the agent is working. Stops
        // when the first audio chunk lands.
        audioFeedback.feedbackForStateChange(.processing)
        await sendTextInternal(message)
    }

    /// Internal: Send text to agent (used by both text input and voice finalization)
    private func sendTextInternal(_ message: String) async {
        do {
            currentAgentResponseId = UUID()

            // We're starting a fresh turn — re-open the audio player's
            // chunk gate. If the previous turn ended via barge-in, the
            // gate was closed to drop late server-streamed chunks for
            // the abandoned response. Now that we're requesting a new
            // response, audio chunks arriving from here on are for the
            // current turn and should be accepted.
            streamingAudioPlayer?.resumeAcceptingChunks()

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

    /// Hands-free mic mute. Doesn't tear down STT — the WebSocket
    /// stays open and audio continues to flow from VoiceService;
    /// `setupSTTCallbacks` checks `isMicMuted` before forwarding any
    /// frames. Cheap toggle so users can pause for side conversations
    /// without re-fetching an STT token on every unmute.
    func setMicMuted(_ muted: Bool) {
        let wasMuted = isMicMuted
        isMicMuted = muted
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
        }
    }

    /// Update the active conversation mode. Called by the view model
    /// after reading @AppStorage; idempotent.
    func setConversationMode(_ mode: ConversationMode) {
        conversationMode = mode
        // Hands-free needs AEC during TTS playback so Halo's voice
        // doesn't bleed into the open mic and trigger false barge-in
        // / silence detection. PTT mutes the mic during TTS so it can
        // use the louder .default audio session mode.
        streamingAudioPlayer?.needsAECDuringPlayback = (mode == .handsFree)
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

        // Belt-and-suspenders: the per-event stops at the .agentResponse,
        // .audioChunk, and .error sites missed several transitions
        // (manual disconnect, error fallthroughs, etc.) and the
        // thinking-pulse haptic kept ticking forever — even after the
        // conversation closed. Stopping it on every leave-from-processing
        // catches all of those paths in one place.
        if oldState == .processing && newState != .processing {
            audioFeedback.stopProcessingPulse()
        }

        // Announce state change for accessibility (throttled)
        if oldState != newState {
            announceStateChange(newState)
        }
    }

    private func emitEvent(_ event: ConversationEvent) {
        onEvent?(event)
    }

    private func handleSpeakingFinished() {
        Logger.debug("ConversationCoordinator: handleSpeakingFinished state=\(state) mode=\(conversationMode.rawValue) muted=\(isMicMuted) ack=\(isPlayingAcknowledgment)")

        // The ack audio just finished — but the real agent response
        // is still on the way. Hold state in .processing so the
        // input button doesn't flicker to "Tap to talk".
        if isPlayingAcknowledgment {
            isPlayingAcknowledgment = false
            if state == .speaking {
                setState(.processing)
                // Resume the thinking-pulse — the audio_chunk
                // handler stopped it when the ack chunks landed,
                // and now we're back to genuine waiting until
                // the response chunks start arriving.
                audioFeedback.feedbackForStateChange(.processing)
            }
            return
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
            let wasBargeIn = bargeInRequested
            bargeInRequested = false
            Task { [weak self] in
                // Skip the settling delay on barge-in — the user
                // is already talking and waiting for the mic to
                // pick up; any pause feels like a dropped word.
                // For natural turn ends, 150ms gives the speaker
                // tail + AEC engine time to settle without a
                // perceptible gap (down from 400ms — old value
                // felt sluggish vs ChatGPT/Gemini which resume
                // in <100ms).
                if !wasBargeIn {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
                await self?.startListening()
            }
            return
        }

        // Push-to-talk path (or hands-free with mute / unrecoverable
        // state): just settle to idle so the user can tap to talk.
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
                Task { [weak self] in
                    await self?.sendText(pending)
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
            if streamingAudioPlayer?.isPlaying != true && streamingAudioPlayer?.isBuffering != true {
                setState(.idle)
            }
            currentAgentResponseId = nil
            backfillRecordingAgentResponse(response.message)

        case .audioChunk(let chunk):
            audioFeedback.stopProcessingPulse()
            Logger.debug("ConversationCoordinator: Audio chunk received, player=\(streamingAudioPlayer != nil), isPlaying=\(streamingAudioPlayer?.isPlaying ?? false)")
            streamingAudioPlayer?.appendAudioChunk(chunk.audio)

        case .audioComplete(let complete):
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

            // Only emit the final transcript on the LAST audio_complete.
            // Intermediate events have an empty body anyway, but this
            // double-check keeps the contract clean.
            if !isPartial {
                if isAck || body.isEmpty {
                    isPlayingAcknowledgment = true
                } else {
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
            playAccumulatedAudio(isFinal: !isPartial)

        case .error(let error):
            audioFeedback.stopProcessingPulse()
            setState(.error(error.error))
            audioFeedback.feedbackForStateChange(.error(error.error))

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

    private func playAccumulatedAudio(isFinal: Bool = true) {
        guard !isPrivacyMode, !isMuted else {
            Logger.info("ConversationCoordinator: Skipping audio - privacy=\(isPrivacyMode), muted=\(isMuted)")
            setState(.idle)
            return
        }

        // Move to .speaking on the first buffer that flips us out of
        // .processing — subsequent intermediate audio_completes during
        // sentence-streaming should not bounce state back and forth.
        if state != .speaking {
            setState(.speaking)
        }
        streamingAudioPlayer?.playAccumulatedAudio(isFinal: isFinal)
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
