import XCTest
@testable import Halo_fi_IOS

@MainActor
final class TranscriptCommitGateTests: XCTestCase {
    func testFinalArrivingDuringSendIsNotLost() async {
        let gate = TranscriptCommitGate()
        let result = await gate.wait(timeout: 0.1) { gate.complete() }
        XCTAssertTrue(result)
    }

    func testTimeoutReturnsFailureWithoutHanging() async {
        let gate = TranscriptCommitGate()
        let start = Date()
        let result = await gate.wait(timeout: 0.02) {}
        XCTAssertFalse(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }

    func testCancellationAndDisconnectNeverApprovePartialSpeech() async {
        let gate = TranscriptCommitGate()
        let cancelled = Task { await gate.wait(timeout: 1) {} }
        await Task.yield()
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        XCTAssertFalse(cancelledResult)
        let disconnected = await gate.wait(timeout: 1) { gate.cancel() }
        XCTAssertFalse(disconnected)
    }

    func testSendFailureAndRepeatedFinalsAreSafe() async {
        let gate = TranscriptCommitGate()
        let failed = await gate.wait(timeout: 1) { throw URLError(.networkConnectionLost) }
        XCTAssertFalse(failed)
        gate.complete()
        gate.complete()
        let next = await gate.wait(timeout: 0.02) {}
        XCTAssertFalse(next)
    }

    func testLateCancelledWaitCannotCancelNextWait() async {
        let gate = TranscriptCommitGate()
        let first = Task { await gate.wait(timeout: 1) { gate.complete() } }
        let result = await first.value
        XCTAssertTrue(result)
        first.cancel()
        let next = await gate.wait(timeout: 1) { gate.complete() }
        XCTAssertTrue(next)
    }

    func testFinalCorrectionReplacesPartialBeforeSend() {
        let store = ConversationTranscriptStore()
        store.updateDraft("yes fifty dollars")
        store.commitSegment("no fifteen dollars")
        XCTAssertEqual(store.finalizeDraft(), "no fifteen dollars")
    }
}
