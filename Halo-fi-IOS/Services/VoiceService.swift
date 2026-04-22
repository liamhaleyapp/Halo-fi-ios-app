//
//  VoiceService.swift
//  Halo-fi-IOS
//
//  Audio capture service for voice input. Captures microphone audio and
//  emits buffers via callback when forwarding is enabled.
//
//  Two-phase lifecycle (Phase 7c, Bugs 15 + 16):
//
//    1. preWarmCapture() — called from ConversationCoordinator.connect()
//       when the Conversation view appears. Configures the audio session,
//       builds the engine, installs the tap, and starts the engine. From
//       this point on, every mic buffer is copied into a small circular
//       ring (~700 ms of audio). The tap callback does NOT forward
//       anything to onAudioBuffer yet — the ring is "pre-roll" audio.
//
//    2. startRecording() — called when the user taps to speak. Flushes
//       the ring to onAudioBuffer (oldest first) so the last ~700 ms of
//       audio before the tap is included. Then flips isForwarding=true
//       so subsequent buffers are forwarded live.
//
//    3. stopRecording() — user finished speaking. Flips isForwarding=false
//       and clears the ring so audio from THIS utterance doesn't leak
//       into the NEXT pre-roll. Engine stays hot.
//
//    4. teardownCapture() — called on view disappear. Removes the tap,
//       stops the engine, fully resets.
//
//  startRecording() still auto-prewarms if teardown was called or the
//  engine isn't ready — so callers that don't know about pre-warm still
//  work, just without the ring-buffer benefit.
//

import Foundation
import AVFoundation

@Observable
@MainActor
final class VoiceService: NSObject {
    static let shared = VoiceService()

    /// True while mic buffers are being forwarded to `onAudioBuffer`.
    /// False during pre-warm (capture is happening into the ring only).
    var isRecording = false

    /// True once the engine is running and the ring is capturing.
    /// Pre-warm has succeeded.
    private(set) var isPrewarmed = false

    var isPlaying = false

    /// Callback for audio buffers — set by external consumer (ElevenLabsSTTService).
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    // MARK: - Engine

    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayer?
    private var recordingSession: AVAudioSession?

    // MARK: - Ring buffer (pre-roll)

    /// Fixed capacity: 35 × ~20 ms buffers ≈ 700 ms of pre-roll at 44–48 kHz
    /// with a 1024-frame tap. Captures the opening syllables users otherwise
    /// lose while the STT WebSocket is handshaking or the engine is spinning up.
    private let ringCapacity: Int = 35
    private var ringBuffer: [AVAudioPCMBuffer] = []

    private override init() {
        super.init()
        setupAudioSession()
    }

    // MARK: - Audio session

    private func setupAudioSession() {
        do {
            recordingSession = AVAudioSession.sharedInstance()
            try recordingSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try recordingSession?.setActive(true)
        } catch {
            Logger.error("Failed to setup audio session: \(error)")
        }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setActive(true)
    }

    // MARK: - Pre-warm

    /// Install the tap + start the engine so pre-roll audio is captured
    /// into the ring before the user even taps. Safe to call repeatedly —
    /// no-op if already prewarmed.
    func preWarmCapture() async throws {
        guard !isPrewarmed else { return }
        guard PermissionManager.shared.isMicrophonePermissionGranted else {
            // Don't fail hard — view may pre-warm before permission prompt.
            // startRecording() will request again.
            Logger.debug("VoiceService: Pre-warm skipped — mic permission not granted")
            return
        }

        try activateSession()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            Logger.error("VoiceService: Invalid tap format \(format)")
            throw VoiceError.audioEngineError
        }

        Logger.info("VoiceService: Pre-warming at \(format.sampleRate) Hz, \(format.channelCount) channels")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Defensive copy — some iOS versions reuse the underlying
            // storage after the callback returns. The cost is one memcpy
            // per ~20 ms of audio (negligible).
            guard let copy = Self.copy(buffer) else { return }
            Task { @MainActor in
                self?.handleAudioBuffer(copy)
            }
        }

        try engine.start()
        self.audioEngine = engine
        self.isPrewarmed = true
    }

    /// Fully stop capture. Called on view disappear or session teardown.
    func teardownCapture() {
        guard isPrewarmed || audioEngine != nil else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isPrewarmed = false
        isRecording = false
        ringBuffer.removeAll()
        Logger.info("VoiceService: Capture torn down")
    }

    // MARK: - Recording (forwarding)

    /// Begin forwarding mic buffers to `onAudioBuffer`. Flushes the pre-roll
    /// ring first so the listener receives the last ~700 ms of audio before
    /// this call — important for catching opening syllables that would
    /// otherwise be lost.
    func startRecording() async throws {
        guard !isRecording else { return }

        guard PermissionManager.shared.isMicrophonePermissionGranted else {
            throw VoiceError.microphonePermissionDenied
        }

        // Caller may not have pre-warmed (e.g. test harness). Kick it off
        // now — startRecording remains functional without pre-warm, just
        // without the ring-buffer benefit.
        if !isPrewarmed {
            try await preWarmCapture()
        }

        // Flush ring oldest → newest before flipping to live mode, so the
        // consumer receives audio in chronological order.
        let prerollSnapshot = ringBuffer
        ringBuffer.removeAll()
        for buffer in prerollSnapshot {
            onAudioBuffer?(buffer)
        }

        isRecording = true
        Logger.info("VoiceService: Recording started (flushed \(prerollSnapshot.count) pre-roll buffers)")
    }

    /// Stop forwarding. Engine stays hot for the next utterance; ring is
    /// cleared so this utterance's audio doesn't leak into the next
    /// pre-roll window.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        ringBuffer.removeAll()
        Logger.info("VoiceService: Recording stopped (engine stays warm)")
    }

    // MARK: - Audio buffer handling

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        if isRecording {
            onAudioBuffer?(buffer)
        } else {
            // Pre-roll mode: append to ring, evict oldest when at capacity
            ringBuffer.append(buffer)
            if ringBuffer.count > ringCapacity {
                ringBuffer.removeFirst(ringBuffer.count - ringCapacity)
            }
        }
    }

    /// Copy an AVAudioPCMBuffer's contents into a newly-allocated buffer.
    /// Needed because buffers delivered to an installTap callback may be
    /// recycled by the framework after the callback returns.
    private static func copy(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: src.format,
            frameCapacity: src.frameCapacity
        ) else { return nil }
        copy.frameLength = src.frameLength
        let channels = Int(src.format.channelCount)
        let frames = Int(src.frameLength)

        if let srcFloat = src.floatChannelData, let dstFloat = copy.floatChannelData {
            let bytes = frames * MemoryLayout<Float>.size
            for ch in 0..<channels {
                memcpy(dstFloat[ch], srcFloat[ch], bytes)
            }
        } else if let srcInt16 = src.int16ChannelData, let dstInt16 = copy.int16ChannelData {
            let bytes = frames * MemoryLayout<Int16>.size
            for ch in 0..<channels {
                memcpy(dstInt16[ch], srcInt16[ch], bytes)
            }
        } else {
            // Unsupported format — skip rather than crash
            return nil
        }
        return copy
    }

    // MARK: - Audio playback (one-shot clips)

    func playAudioData(_ audioData: Data) async {
        guard !isPlaying else { return }

        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            Logger.error("Failed to play audio: \(error)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
        }
    }
}

// MARK: - Voice Errors

enum VoiceError: LocalizedError {
    case audioEngineError
    case microphonePermissionDenied
    case recordingError
    case playbackError

    var errorDescription: String? {
        switch self {
        case .audioEngineError:
            return "Failed to initialize audio engine"
        case .microphonePermissionDenied:
            return "Microphone permission is required for voice chat"
        case .recordingError:
            return "Failed to record audio"
        case .playbackError:
            return "Failed to play audio"
        }
    }
}
