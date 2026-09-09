import Foundation

/// Uses audio duration, not callback count. Local detection stops playback
/// without waiting for a recognition server to return a transcript.
struct VoiceBargeInDetector {
    enum Decision { case quiet, candidate, interrupt }
    private var voicedSeconds: Double = 0
    private var quietSeconds: Double = 0

    mutating func observe(rms: Float, duration: Double) -> Decision {
        guard rms.isFinite, duration.isFinite, duration > 0, duration <= 0.25 else { return .quiet }
        if rms >= 0.04 {
            voicedSeconds += duration
            quietSeconds = 0
        } else {
            quietSeconds += duration
            if quietSeconds > 0.06 { reset(); return .quiet }
        }
        if voicedSeconds >= 0.35 { reset(); return .interrupt }
        return voicedSeconds >= 0.06 ? .candidate : .quiet
    }

    mutating func reset() { voicedSeconds = 0; quietSeconds = 0 }
}

/// Retain only a short rolling onset before speech detection. Once interrupted,
/// preserve the entire input through recognizer recovery or explicitly fail.
struct VoiceInterruptionAudio<Element> {
    private var entries: [(Element, Double)] = []
    private var duration: Double = 0
    private(set) var isInterrupted = false

    mutating func append(_ value: Element, duration seconds: Double) -> Bool {
        guard seconds.isFinite, seconds > 0, seconds <= 0.25 else { return false }
        if isInterrupted {
            guard duration + seconds <= 2, entries.count < 150 else { return false }
        } else {
            while !entries.isEmpty && (duration + seconds > 0.5 || entries.count >= 75) {
                duration -= entries.removeFirst().1
            }
        }
        entries.append((value, seconds)); duration += seconds
        return true
    }

    mutating func beginInterruption() { isInterrupted = true }

    mutating func takeInterruptedAudio() -> [Element] {
        let result = isInterrupted ? entries.map { $0.0 } : []
        reset()
        return result
    }

    mutating func reset() {
        entries.removeAll(); duration = 0; isInterrupted = false
    }
}
