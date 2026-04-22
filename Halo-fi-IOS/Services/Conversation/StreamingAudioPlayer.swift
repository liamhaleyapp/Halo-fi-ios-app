//
//  StreamingAudioPlayer.swift
//  Halo-fi-IOS
//
//  True streaming playback for ElevenLabs TTS — each base64 chunk is
//  decoded as raw 16-bit PCM @ 16 kHz mono, converted to Float32, and
//  scheduled on an AVAudioPlayerNode the moment it arrives. No more
//  accumulate-entire-stream-then-play-once latency.
//
//  Expected backend format: `?output_format=pcm_16000` on the ElevenLabs
//  WebSocket URL (configured in elevenlabs_service.py). If the backend
//  reverts to MP3, playback silently yields zero samples — the chunk
//  decoder logs the mismatch.
//
//  Interface is backward-compatible with the MP3 accumulator:
//    - appendAudioChunk(_:) pipes a chunk into the engine immediately
//    - playAccumulatedAudio() signals end-of-stream; once the last
//      scheduled buffer drains, onPlaybackFinished fires.
//

import AVFoundation

@MainActor
final class StreamingAudioPlayer {
    // MARK: - Public State

    private(set) var isPlaying: Bool = false
    private(set) var isMuted: Bool = false
    /// Returns true between the first scheduled chunk and the final drain.
    var isBuffering: Bool { streamActive && !streamComplete }

    // MARK: - Callbacks

    var onPlaybackFinished: (() -> Void)?

    /// Playback rate (0.5 to 2.0). Applied via AVAudioUnitTimePitch on
    /// the player chain. Can be changed between chunks — the new rate
    /// takes effect on the next scheduled buffer.
    var playbackRate: Float = 1.0 {
        didSet { timePitchNode?.rate = playbackRate }
    }

    // MARK: - Private — engine

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?

    // MARK: - Private — stream state

    /// Incoming chunks arrive as raw Int16 PCM at this sample rate (matches
    /// the backend's ?output_format=pcm_16000 setting).
    private let sourceSampleRate: Double = 16_000
    private let sourceChannels: AVAudioChannelCount = 1

    /// True once the first chunk has been scheduled. Used to lazy-init the
    /// audio engine on first arrival rather than up front.
    private var streamActive = false
    /// True once playAccumulatedAudio() has been called — signals that no
    /// more chunks will arrive. When the last pending buffer finishes,
    /// we fire onPlaybackFinished.
    private var streamComplete = false
    /// Scheduled-but-not-yet-drained buffer count.
    private var pendingBufferCount = 0

    // MARK: - Audio session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .duckOthers]
            )
            try session.setActive(true)
            Logger.info("StreamingAudioPlayer: Audio session configured")
        } catch {
            Logger.error("StreamingAudioPlayer: Failed to configure audio session: \(error)")
        }
    }

    // MARK: - Public API

    /// Decode a base64 PCM chunk and schedule it for immediate playback.
    /// The engine is lazily created on the first chunk.
    func appendAudioChunk(_ base64Audio: String) {
        guard !isMuted else {
            Logger.debug("StreamingAudioPlayer: Dropping chunk (muted)")
            return
        }
        guard let pcmData = Data(base64Encoded: base64Audio) else {
            Logger.error("StreamingAudioPlayer: Invalid base64 audio data")
            return
        }
        guard !pcmData.isEmpty else { return }

        if audioEngine == nil {
            do {
                try startEngine()
            } catch {
                Logger.error("StreamingAudioPlayer: Engine start failed: \(error)")
                return
            }
        }

        guard let buffer = makeFloat32Buffer(from: pcmData) else { return }
        guard let player = playerNode else { return }

        streamActive = true
        isPlaying = true
        pendingBufferCount += 1

        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in self?.onBufferFinished() }
        }
    }

    /// Signal end-of-stream. Once the last scheduled buffer drains,
    /// onPlaybackFinished will fire. If the stream was empty, fire
    /// immediately so the caller can reset UI state.
    func playAccumulatedAudio() {
        streamComplete = true
        if !streamActive {
            // Empty stream — nothing was ever scheduled.
            finalizeIfDrained()
        } else {
            finalizeIfDrained()
        }
    }

    /// Immediately stop playback and tear down the engine.
    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        timePitchNode = nil

        let wasActive = streamActive
        streamActive = false
        streamComplete = false
        pendingBufferCount = 0

        if isPlaying || wasActive {
            isPlaying = false
            onPlaybackFinished?()
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted { stop() }
    }

    // MARK: - Private — engine lifecycle

    private func startEngine() throws {
        configureAudioSession()

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = playbackRate

        // Player emits Float32 (see makeFloat32Buffer); time-pitch
        // requires Float32; mainMixer accepts anything.
        guard let playerFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: sourceChannels,
            interleaved: false
        ) else {
            throw NSError(domain: "StreamingAudioPlayer", code: 1)
        }

        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: playerFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: playerFormat)

        try engine.start()
        player.play()

        self.audioEngine = engine
        self.playerNode = player
        self.timePitchNode = timePitch

        Logger.info("StreamingAudioPlayer: Engine started (PCM \(Int(sourceSampleRate))Hz mono)")
    }

    // MARK: - Private — buffer construction

    /// Convert a Data payload of raw little-endian Int16 PCM mono samples
    /// at `sourceSampleRate` into an AVAudioPCMBuffer in Float32 format.
    /// Float32 is required downstream by AVAudioUnitTimePitch.
    private func makeFloat32Buffer(from int16Data: Data) -> AVAudioPCMBuffer? {
        let sampleCount = int16Data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return nil }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: sourceChannels,
            interleaved: false
        ) else {
            Logger.error("StreamingAudioPlayer: Failed to build PCM format")
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else {
            Logger.error("StreamingAudioPlayer: Failed to allocate PCM buffer")
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        guard let dest = buffer.floatChannelData?[0] else { return nil }

        // Int16 → Float32 normalized to [-1.0, 1.0].
        // Using 1/32768 (Int16.max + 1) instead of 1/32767 avoids a
        // tiny asymmetry at the positive peak — imperceptible either way.
        let scale: Float = 1.0 / 32768.0
        int16Data.withUnsafeBytes { rawBuf in
            guard let src = rawBuf.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for i in 0..<sampleCount {
                dest[i] = Float(src[i]) * scale
            }
        }

        return buffer
    }

    // MARK: - Private — stream lifecycle

    private func onBufferFinished() {
        pendingBufferCount = max(0, pendingBufferCount - 1)
        finalizeIfDrained()
    }

    private func finalizeIfDrained() {
        guard streamComplete, pendingBufferCount == 0 else { return }
        finishPlayback()
    }

    private func finishPlayback() {
        guard streamActive || isPlaying else {
            // Empty stream — still notify so the caller can reset UI.
            streamComplete = false
            streamActive = false
            onPlaybackFinished?()
            return
        }

        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        timePitchNode = nil

        isPlaying = false
        streamActive = false
        streamComplete = false

        Logger.info("StreamingAudioPlayer: Playback finished (drained)")
        onPlaybackFinished?()
    }
}
