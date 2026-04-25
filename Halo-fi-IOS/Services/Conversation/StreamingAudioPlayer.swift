//
//  StreamingAudioPlayer.swift
//  Halo-fi-IOS
//
//  Plays accumulated MP3 audio from ElevenLabs TTS responses. Chunks
//  arrive over the agent WebSocket as base64 strings; we accumulate them
//  in `mp3Data` and play the whole buffer at audio_complete via
//  AVAudioPlayer.
//
//  Why AVAudioPlayer (not AVAudioEngine):
//  ─────────────────────────────────────
//  The previous implementation used AVAudioEngine + AVAudioPlayerNode +
//  AVAudioUnitTimePitch. AVAudioEngine has a long-running issue in the
//  iOS Simulator where playback fails silently when the audio session
//  is .playAndRecord (which we need for the mic). The user heard
//  haptics + system sounds (AVAudioPlayer) but never agent TTS
//  (AVAudioEngine) — a clean diagnostic.
//
//  We have the full MP3 data in memory by the time audio_complete fires,
//  so streaming via the engine wasn't buying anything. AVAudioPlayer
//  works in both sim and device, supports playbackRate via enableRate +
//  rate, and is simpler to reason about. The interface stayed
//  unchanged so the call sites in ConversationCoordinator are
//  untouched.
//

import AVFoundation

@MainActor
final class StreamingAudioPlayer: NSObject {
    // MARK: - Public State

    private(set) var isPlaying: Bool = false
    private(set) var isMuted: Bool = false
    var isBuffering: Bool { !mp3Data.isEmpty }

    // MARK: - Callbacks

    var onPlaybackFinished: (() -> Void)?

    /// Playback rate (0.5–2.0). Applied via AVAudioPlayer.rate when
    /// playback starts; changing it mid-playback is honored on the
    /// next play() but not retroactively.
    var playbackRate: Float = 1.0

    // MARK: - Private

    private var audioPlayer: AVAudioPlayer?
    private var mp3Data = Data()

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

    /// Append a base64-encoded MP3 chunk to the accumulator.
    func appendAudioChunk(_ base64Audio: String) {
        guard let rawData = Data(base64Encoded: base64Audio) else {
            Logger.error("StreamingAudioPlayer: Invalid base64 audio data")
            return
        }
        mp3Data.append(rawData)
        Logger.debug("StreamingAudioPlayer: Accumulated \(mp3Data.count) bytes total")
    }

    /// Play the accumulated MP3 data via AVAudioPlayer. Called when
    /// audio_complete arrives from the WebSocket.
    func playAccumulatedAudio() {
        guard !isMuted else {
            Logger.info("StreamingAudioPlayer: Skipping playback (muted)")
            mp3Data = Data()
            onPlaybackFinished?()
            return
        }

        guard !mp3Data.isEmpty else {
            Logger.warning("StreamingAudioPlayer: No audio data accumulated")
            onPlaybackFinished?()
            return
        }

        Logger.info("StreamingAudioPlayer: Playing \(mp3Data.count) bytes of MP3 data")
        configureAudioSession()

        do {
            let player = try AVAudioPlayer(data: mp3Data)
            player.delegate = self
            player.enableRate = true
            player.rate = playbackRate
            guard player.prepareToPlay() else {
                Logger.error("StreamingAudioPlayer: prepareToPlay returned false")
                mp3Data = Data()
                onPlaybackFinished?()
                return
            }
            guard player.play() else {
                Logger.error("StreamingAudioPlayer: play() returned false")
                mp3Data = Data()
                onPlaybackFinished?()
                return
            }
            self.audioPlayer = player
            self.isPlaying = true
            // Clear the accumulator now that we've handed it to the player —
            // AVAudioPlayer copies the bytes internally on init.
            mp3Data = Data()
            Logger.info("StreamingAudioPlayer: Playback started (\(player.duration)s, rate=\(playbackRate))")
        } catch {
            Logger.error("StreamingAudioPlayer: AVAudioPlayer init failed: \(error)")
            mp3Data = Data()
            onPlaybackFinished?()
        }
    }

    /// Immediately stop playback and clear state.
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        mp3Data = Data()

        if isPlaying {
            isPlaying = false
            onPlaybackFinished?()
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted { stop() }
    }
}

// MARK: - AVAudioPlayerDelegate

extension StreamingAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            Logger.info("StreamingAudioPlayer: Playback finished (success=\(flag))")
            self.audioPlayer = nil
            self.isPlaying = false
            self.onPlaybackFinished?()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            Logger.error("StreamingAudioPlayer: Decode error: \(error?.localizedDescription ?? "unknown")")
            self.audioPlayer = nil
            self.isPlaying = false
            self.onPlaybackFinished?()
        }
    }
}
