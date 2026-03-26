//
//  StreamingAudioPlayer.swift
//  Halo-fi-IOS
//
//  Streaming audio playback for ElevenLabs TTS responses.
//  Accumulates base64-encoded MP3 chunks from the WebSocket,
//  then decodes and plays via AVAudioEngine + AVAudioPlayerNode.
//

import AVFoundation
import UIKit

@MainActor
final class StreamingAudioPlayer {
    // MARK: - Public State

    private(set) var isPlaying: Bool = false
    private(set) var isMuted: Bool = false

    // MARK: - Callbacks

    var onPlaybackFinished: (() -> Void)?

    // MARK: - Private

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    /// Accumulated raw MP3 bytes from all chunks
    private var mp3Data = Data()

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.duckOthers]
            )
            try session.setActive(true)
            Logger.info("StreamingAudioPlayer: Audio session configured")
        } catch {
            Logger.error("StreamingAudioPlayer: Failed to configure audio session: \(error)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } catch {
            Logger.error("StreamingAudioPlayer: Failed to deactivate audio session: \(error)")
        }
    }

    // MARK: - Public API

    /// Append a base64-encoded audio chunk to the accumulator.
    func appendAudioChunk(_ base64Audio: String) {
        guard let rawData = Data(base64Encoded: base64Audio) else {
            Logger.error("StreamingAudioPlayer: Invalid base64 audio data")
            return
        }

        mp3Data.append(rawData)
        Logger.debug("StreamingAudioPlayer: Accumulated \(mp3Data.count) bytes total")
    }

    /// Decode the accumulated MP3 data and play it.
    func playAccumulatedAudio() {
        guard !isMuted, !UIAccessibility.isVoiceOverRunning else {
            Logger.info("StreamingAudioPlayer: Skipping playback (muted or VoiceOver)")
            mp3Data = Data()
            return
        }

        guard !mp3Data.isEmpty else {
            Logger.warning("StreamingAudioPlayer: No audio data accumulated")
            onPlaybackFinished?()
            return
        }

        Logger.info("StreamingAudioPlayer: Decoding \(mp3Data.count) bytes of MP3 data")

        // Write accumulated MP3 to temp file for AVAudioFile to decode
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")

        do {
            try mp3Data.write(to: tempURL)
        } catch {
            Logger.error("StreamingAudioPlayer: Failed to write temp MP3: \(error)")
            mp3Data = Data()
            onPlaybackFinished?()
            return
        }

        // Clear accumulator now that we've written it
        mp3Data = Data()

        do {
            let audioFile = try AVAudioFile(forReading: tempURL)
            let processingFormat = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)

            Logger.info("StreamingAudioPlayer: Decoded MP3 — \(frameCount) frames, \(processingFormat.sampleRate)Hz, \(processingFormat.channelCount)ch")

            guard frameCount > 0 else {
                Logger.warning("StreamingAudioPlayer: Empty audio file")
                try? FileManager.default.removeItem(at: tempURL)
                onPlaybackFinished?()
                return
            }

            guard let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: frameCount
            ) else {
                Logger.error("StreamingAudioPlayer: Failed to create PCM buffer")
                try? FileManager.default.removeItem(at: tempURL)
                onPlaybackFinished?()
                return
            }

            try audioFile.read(into: pcmBuffer)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            // Set up engine and play
            configureAudioSession()

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: processingFormat)

            try engine.start()
            player.play()

            self.audioEngine = engine
            self.playerNode = player
            self.isPlaying = true

            Logger.info("StreamingAudioPlayer: Playing audio (\(frameCount) frames)")

            player.scheduleBuffer(pcmBuffer) { [weak self] in
                Task { @MainActor in
                    self?.finishPlayback()
                }
            }

        } catch {
            Logger.error("StreamingAudioPlayer: Failed to decode/play MP3: \(error)")
            try? FileManager.default.removeItem(at: tempURL)
            onPlaybackFinished?()
        }
    }

    /// Immediately stop playback and tear down the engine.
    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        mp3Data = Data()

        if isPlaying {
            isPlaying = false
            // Don't deactivate audio session here — VoiceService will
            // reconfigure it for recording if the user starts listening next.
            onPlaybackFinished?()
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted { stop() }
    }

    // MARK: - Private Helpers

    private func finishPlayback() {
        guard isPlaying else { return }

        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        isPlaying = false
        deactivateAudioSession()

        Logger.info("StreamingAudioPlayer: Playback finished")
        onPlaybackFinished?()
    }
}
