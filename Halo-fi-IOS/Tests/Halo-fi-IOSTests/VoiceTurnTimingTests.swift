import XCTest
@testable import Halo_fi_IOS

final class VoiceTurnTimingTests: XCTestCase {
    func testQueuedAcknowledgmentDoesNotCountAsFirstAnswer() {
        var timing = VoiceTurnTiming()
        timing.begin(turnId: "t", sentAt: 10, endedAt: 9.5, lastSpeechAt: 8.5)
        let ack = timing.playback(.init(turnId: "t", isAcknowledgment: true), at: 11, outputEnabled: true)
        let answer = timing.playback(.init(turnId: "t", isAcknowledgment: false), at: 12, outputEnabled: true)
        XCTAssertEqual(ack?["stage"], "acknowledgment")
        XCTAssertEqual(answer?["stage"], "answer")
        XCTAssertEqual(answer?["send_to_playback_ms"], "2000")
        XCTAssertEqual(answer?["turn_end_to_playback_ms"], "2500")
        XCTAssertEqual(answer?["detected_speech_to_playback_ms"], "3500")
        XCTAssertNil(timing.playback(.init(turnId: "t", isAcknowledgment: false), at: 13, outputEnabled: true))
    }

    func testOldTurnGreetingAndMutedPlaybackCannotProduceMeasurements() {
        var timing = VoiceTurnTiming()
        timing.begin(turnId: "new", sentAt: 10)
        XCTAssertNil(timing.playback(.init(turnId: "old", isAcknowledgment: false), at: 11, outputEnabled: true))
        XCTAssertNil(timing.playback(.init(turnId: nil, isAcknowledgment: false), at: 11, outputEnabled: true))
        XCTAssertNil(timing.playback(.init(turnId: "new", isAcknowledgment: false), at: 11, outputEnabled: false))
        XCTAssertNotNil(timing.playback(.init(turnId: "new", isAcknowledgment: false), at: 12, outputEnabled: true))
        timing.reset()
        XCTAssertNil(timing.playback(.init(turnId: "new", isAcknowledgment: true), at: 13, outputEnabled: true))
    }

    func testErrorSpeechIsNotReportedAsUsefulAnswer() {
        var timing = VoiceTurnTiming()
        timing.begin(turnId: "t", sentAt: 10)
        let error = timing.playback(.init(turnId: "t", isAcknowledgment: false, isError: true),
                                    at: 11, outputEnabled: true)
        XCTAssertEqual(error?["stage"], "error")
        let answer = timing.playback(.init(turnId: "t", isAcknowledgment: false), at: 12, outputEnabled: true)
        XCTAssertEqual(answer?["stage"], "answer")
    }

    func testInvalidOrExpiredTimesAreNotRecorded() {
        var timing = VoiceTurnTiming()
        timing.begin(turnId: "t", sentAt: 10)
        for value in [Double.nan, .infinity, 9, 191] {
            XCTAssertNil(timing.playback(.init(turnId: "t", isAcknowledgment: false), at: value, outputEnabled: true))
        }
        let valid = timing.playback(.init(turnId: "t", isAcknowledgment: false), at: 11, outputEnabled: true)
        XCTAssertEqual(valid?["send_to_playback_ms"], "1000")
        XCTAssertNil(valid?["turn_end_to_playback_ms"])
    }
}
