import Foundation

/// Identity follows each queued sentence, including when an answer queues
/// behind its acknowledgment. No transcript, amount, or account data.
struct VoicePlaybackMarker {
    let turnId: String?
    let isAcknowledgment: Bool
    var isError: Bool = false
}

/// All instants use ProcessInfo.systemUptime on the same device. Playback
/// means AVAudioPlayer accepted play(), not a microphone-measured sound onset.
struct VoiceTurnTiming {
    private var turnId: String?
    private var sentAt: TimeInterval = 0
    private var endedAt: TimeInterval?
    private var lastSpeechAt: TimeInterval?
    private var reported: Set<String> = []

    mutating func begin(turnId: String, sentAt: TimeInterval,
                        endedAt: TimeInterval? = nil, lastSpeechAt: TimeInterval? = nil) {
        self.turnId = turnId
        self.sentAt = sentAt
        self.endedAt = endedAt
        self.lastSpeechAt = lastSpeechAt
        reported.removeAll()
    }

    mutating func reset() { self = VoiceTurnTiming() }

    mutating func playback(_ marker: VoicePlaybackMarker, at now: TimeInterval,
                           outputEnabled: Bool) -> [String: String]? {
        guard outputEnabled, let turnId, marker.turnId == turnId else { return nil }
        let stage = marker.isError ? "error" : (marker.isAcknowledgment ? "acknowledgment" : "answer")
        guard !reported.contains(stage), let sentMs = milliseconds(from: sentAt, to: now) else { return nil }
        reported.insert(stage)
        var fields = ["turn_id": turnId, "stage": stage,
                      "send_to_playback_ms": String(sentMs)]
        if let endedAt, let ms = milliseconds(from: endedAt, to: now) {
            fields["turn_end_to_playback_ms"] = String(ms)
        }
        if let lastSpeechAt, let ms = milliseconds(from: lastSpeechAt, to: now) {
            fields["detected_speech_to_playback_ms"] = String(ms)
        }
        return fields
    }

    private func milliseconds(from start: TimeInterval, to end: TimeInterval) -> Int? {
        let seconds = end - start
        guard seconds.isFinite, seconds >= 0, seconds <= 180 else { return nil }
        return Int((seconds * 1000).rounded())
    }
}
