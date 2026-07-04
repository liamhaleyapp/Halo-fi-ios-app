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
    /// When true, appendAudioChunk drops incoming bytes instead of
    /// buffering them. Set by stopAndDiscardPending() (called from
    /// barge-in) so server-side TTS chunks that are still in flight
    /// after we've decided to interrupt don't refill mp3Data and
    /// confuse the coordinator's `isBuffering` check.
    private var isAcceptingChunks: Bool = true

    /// Queue of completed audio buffers (one per sentence in the
    /// new sentence-streaming protocol). When the current player
    /// finishes, the next buffer in this queue is dequeued and
    /// played without any state-flip back to .idle. Empty between
    /// turns and any time we're not chunked.
    private var pendingBuffers: [Data] = []

    /// True once an audio_complete with is_partial=false has landed,
    /// telling us no more buffers will arrive for this turn. When the
    /// queue drains AND this is true, we fire onPlaybackFinished so
    /// ConversationCoordinator can transition out of .speaking.
    /// While false, queue drains are silent — we just wait for the
    /// next buffer.
    private var isFinalQueued: Bool = false

    // MARK: - Audio session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Always .voiceChat for AEC. The "loud TTS" win we got from
            // .default mode came at the cost of the mic capturing
            // Halo's own voice from the speaker on the next turn —
            // user-visible bug: the user's transcript started with
            // Halo's last sentence verbatim. AEC keeps audio clean
            // in both PTT and hands-free at the expense of slightly
            // lower playback volume on the built-in speaker. Users
            // can crank system volume; corrupt transcripts can't be
            // fixed by the user.
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
            )
            try session.setActive(true)

            // `.voiceChat` defaults to the receiver (earpiece) on
            // .playAndRecord even with .defaultToSpeaker set — the
            // option is supposed to override that but is unreliable
            // on iOS 17+. Users heard Halo "way too quiet" because
            // audio was routing through the small phone-call speaker
            // instead of the loud bottom speaker. Force the speaker
            // explicitly here, BUT only when no headphones/Bluetooth
            // route is active so AirPods users still get audio in
            // their AirPods.
            Self.forceSpeakerIfNoHeadphones(session: session)

            let routeDescription = session.currentRoute.outputs
                .map { $0.portType.rawValue }
                .joined(separator: ",")
            Logger.info("StreamingAudioPlayer: Audio session configured (.voiceChat) route=\(routeDescription)")
        } catch {
            Logger.error("StreamingAudioPlayer: Failed to configure audio session: \(error)")
        }
    }

    /// Override the output port to the loud speaker unless a headset
    /// or Bluetooth output is currently routed. Apple's docs note that
    /// `.defaultToSpeaker` on a `.voiceChat` session "may" override the
    /// receiver default — in practice it often doesn't. This explicit
    /// override is the reliable path.
    ///
    /// Marked `nonisolated` so VoiceService (and other future callers
    /// that aren't MainActor) can use it without an await dance —
    /// AVAudioSession's mutators are thread-safe and have no MainActor
    /// requirement of their own.
    nonisolated static func forceSpeakerIfNoHeadphones(session: AVAudioSession) {
        let headphoneTypes: Set<AVAudioSession.Port> = [
            .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP,
            .airPlay, .carAudio, .usbAudio,
        ]
        let isOnHeadphones = session.currentRoute.outputs.contains {
            headphoneTypes.contains($0.portType)
        }
        guard !isOnHeadphones else { return }
        do {
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            Logger.error("StreamingAudioPlayer: overrideOutputAudioPort(.speaker) failed: \(error)")
        }
    }

    // MARK: - Public API

    /// Append a base64-encoded MP3 chunk to the accumulator. Drops the
    /// chunk silently when we're in post-barge-in discard mode — the
    /// server hasn't yet been told to stop streaming, so chunks for the
    /// abandoned response can still arrive after the user has interrupted.
    func appendAudioChunk(_ base64Audio: String) {
        guard isAcceptingChunks else {
            Logger.debug("StreamingAudioPlayer: dropping post-barge-in chunk")
            return
        }
        guard let rawData = Data(base64Encoded: base64Audio) else {
            Logger.error("StreamingAudioPlayer: Invalid base64 audio data")
            return
        }
        mp3Data.append(rawData)
        Logger.debug("StreamingAudioPlayer: Accumulated \(mp3Data.count) bytes total")
    }

    /// Variant of stop() that suppresses any further incoming chunks
    /// until resumeAcceptingChunks() is called. Used by barge-in: we
    /// stop the local player immediately, but the server is still
    /// streaming TTS for the abandoned response. Without this gate
    /// those chunks would refill mp3Data, making isBuffering report
    /// true and causing ConversationCoordinator.startListening() to
    /// bail out instead of resuming the mic.
    func stopAndDiscardPending() {
        isAcceptingChunks = false
        stop()
    }

    /// Re-open the chunk gate. Called by ConversationCoordinator the
    /// moment the user has committed a new turn — any audio that
    /// arrives from here on is for the new agent response and should
    /// be accepted.
    func resumeAcceptingChunks() {
        isAcceptingChunks = true
    }

    /// Snapshot the accumulated MP3 buffer onto the playback queue.
    /// If nothing is currently playing, immediately starts the first
    /// queued buffer. If something IS playing, the new buffer is
    /// appended and will be played when the current player finishes
    /// (no state-flip back to .idle in between).
    ///
    /// Pass `isFinal: true` for the LAST audio_complete of a turn —
    /// when the queue eventually drains, onPlaybackFinished fires so
    /// ConversationCoordinator can leave .speaking. Pass false for
    /// intermediate sentence-by-sentence audio_completes.
    ///
    /// The legacy single-buffer behavior is preserved when callers
    /// pass isFinal: true (default) and only one buffer is ever
    /// queued — the same code path runs.
    func playAccumulatedAudio(isFinal: Bool = true) {
        // Drop late audio_complete events for an abandoned response
        // (post-barge-in). Without this, a stale "final" audio_complete
        // for the response the user interrupted would fire
        // onPlaybackFinished and bounce ConversationCoordinator out of
        // the listening session it just opened.
        guard isAcceptingChunks else {
            Logger.debug("StreamingAudioPlayer: dropping post-barge-in audio_complete (isFinal=\(isFinal))")
            return
        }

        if isFinal { isFinalQueued = true }

        guard !isMuted else {
            Logger.info("StreamingAudioPlayer: Skipping playback (muted)")
            mp3Data = Data()
            pendingBuffers.removeAll()
            if isFinal {
                isFinalQueued = false
                onPlaybackFinished?()
            }
            return
        }

        if !mp3Data.isEmpty {
            pendingBuffers.append(mp3Data)
            mp3Data = Data()
        }

        if !isPlaying {
            playNextBuffer()
        }
    }

    /// Pull the next buffer off the queue and start playback. Called
    /// initially by playAccumulatedAudio and again by the delegate
    /// when each buffer finishes.
    private func playNextBuffer() {
        guard let nextData = pendingBuffers.first else {
            // Queue empty.
            isPlaying = false
            audioPlayer = nil
            // The turn is over only if the final audio_complete has
            // already arrived. Otherwise we're between sentences and
            // waiting for the next buffer to land.
            if isFinalQueued {
                isFinalQueued = false
                onPlaybackFinished?()
            }
            return
        }

        pendingBuffers.removeFirst()
        Logger.info("StreamingAudioPlayer: Playing \(nextData.count) bytes (queue=\(pendingBuffers.count) remaining)")
        configureAudioSession()

        do {
            let player = try AVAudioPlayer(data: nextData)
            player.delegate = self
            player.enableRate = true
            player.rate = playbackRate
            // Max gain at the player. AVAudioPlayer.volume is the per-
            // player gain (0...1) multiplied with system volume; setting
            // it to 1.0 is the default but we set it explicitly as
            // protection against any future code path that lowers it
            // (mute toggles, ducking experiments, etc.).
            player.volume = 1.0
            guard player.prepareToPlay(), player.play() else {
                Logger.error("StreamingAudioPlayer: failed to start playback for queued buffer; skipping")
                playNextBuffer()
                return
            }
            self.audioPlayer = player
            self.isPlaying = true
            Logger.info("StreamingAudioPlayer: Playback started (\(player.duration)s, rate=\(playbackRate))")
        } catch {
            Logger.error("StreamingAudioPlayer: AVAudioPlayer init failed: \(error)")
            playNextBuffer()
        }
    }

    /// Immediately stop playback and clear state.
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        mp3Data = Data()
        pendingBuffers.removeAll()
        let wasFinalPending = isFinalQueued
        isFinalQueued = false

        if isPlaying || wasFinalPending {
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
            Logger.info("StreamingAudioPlayer: Buffer finished (success=\(flag), queue=\(self.pendingBuffers.count))")
            // Advance the queue. If more buffers are waiting, plays
            // the next one. If empty AND the final audio_complete
            // has already landed, fires onPlaybackFinished. If empty
            // AND we're still mid-turn (waiting for more sentences),
            // stays silent and resumes when the next buffer is
            // queued via playAccumulatedAudio.
            self.audioPlayer = nil
            self.isPlaying = false
            self.playNextBuffer()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            Logger.error("StreamingAudioPlayer: Decode error: \(error?.localizedDescription ?? "unknown")")
            self.audioPlayer = nil
            self.isPlaying = false
            self.playNextBuffer()
        }
    }
}
