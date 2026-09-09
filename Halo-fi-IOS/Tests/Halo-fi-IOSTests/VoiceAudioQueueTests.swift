import XCTest
@testable import Halo_fi_IOS

final class VoiceAudioQueueTests: XCTestCase {
    func testSlowNetworkCannotBuildUnlimitedBacklog() {
        var queue = VoiceAudioQueue<Int>(maxDuration: 2, maxCount: 100)
        XCTAssertTrue(queue.append(1, duration: 1))
        XCTAssertTrue(queue.append(2, duration: 1))
        XCTAssertTrue(!queue.append(3, duration: 0.01))
        XCTAssertTrue(queue.popFirst() == 1)
        XCTAssertTrue(queue.append(3, duration: 1))
        XCTAssertTrue(queue.popFirst() == 2)
        XCTAssertTrue(queue.popFirst() == 3)
        XCTAssertTrue(queue.isEmpty)
    }

    func testInvalidFramesAndTinyFrameFloodAreRejected() {
        var queue = VoiceAudioQueue<Int>(maxCount: 2)
        XCTAssertTrue(!queue.append(0, duration: 0))
        XCTAssertTrue(!queue.append(0, duration: .nan))
        XCTAssertTrue(queue.append(1, duration: 0.001))
        XCTAssertTrue(queue.append(2, duration: 0.001))
        XCTAssertTrue(!queue.append(3, duration: 0.001))
        queue.removeAll()
        XCTAssertTrue(queue.duration == 0)
        XCTAssertTrue(queue.popFirst() == nil)
    }
}
