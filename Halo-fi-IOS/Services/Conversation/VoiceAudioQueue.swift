import Foundation

/// A bounded, ordered microphone backlog. Overflow rejects the whole turn;
/// callers must not send a partial confirmation after losing audio.
struct VoiceAudioQueue<Element> {
    private var entries: [(Element, Double)] = []
    private(set) var duration: Double = 0
    let maxDuration: Double
    let maxCount: Int
    var isEmpty: Bool { entries.isEmpty }

    init(maxDuration: Double = 2, maxCount: Int = 100) {
        self.maxDuration = maxDuration
        self.maxCount = maxCount
    }

    mutating func append(_ item: Element, duration seconds: Double) -> Bool {
        guard seconds.isFinite, seconds > 0, entries.count < maxCount,
              duration + seconds <= maxDuration else { return false }
        entries.append((item, seconds))
        duration += seconds
        return true
    }

    mutating func popFirst() -> Element? {
        guard !entries.isEmpty else { return nil }
        let next = entries.removeFirst()
        duration = max(0, duration - next.1)
        return next.0
    }

    mutating func removeAll() {
        entries.removeAll()
        duration = 0
    }
}
