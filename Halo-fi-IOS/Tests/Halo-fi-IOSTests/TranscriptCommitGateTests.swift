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

private final class FakeSpeechSocket: SpeechSocket {
    var state: URLSessionTask.State = .suspended
    var closeReason: Data?
    var receiver: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    var sends = 0
    var deferSendFailure: CheckedContinuation<Void, Error>?
    var holdSend = false
    func resume() { state = .running }
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        state = .completed
        // Deliberately allow a late callback, like a cancelled URLSession task.
    }
    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        sends += 1
        if holdSend { try await withCheckedThrowingContinuation { deferSendFailure = $0 } }
    }
    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await withCheckedThrowingContinuation { receiver = $0 }
    }
    func emit(_ text: String) {
        let pending = receiver; receiver = nil
        pending?.resume(returning: .string(text))
    }
    func finish() {
        let pending = receiver; receiver = nil
        pending?.resume(throwing: URLError(.cancelled))
    }
}

@MainActor
final class SpeechReadinessTests: XCTestCase {
    private func makeService(_ sockets: [FakeSpeechSocket], timeout: TimeInterval = 1) -> ElevenLabsSTTService {
        let network = MockNetworkService()
        network.setMockResponse(STTTokenResponse(token: "test", expiresAt: nil,
            modelId: "scribe_v2_realtime", websocketUrl: "wss://speech.invalid",
            config: .init(audioFormat: "pcm_16000", sampleRate: 16000,
                commitStrategy: "vad", languageCode: "en", includeTimestamps: false, contextPrompt: nil)),
            for: APIEndpoints.Agent.sttToken)
        var index = 0
        return ElevenLabsSTTService(networkService: network, readinessTimeout: timeout) { _ in
            let socket = sockets[index]; index += 1; return socket
        }
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Expected asynchronous operation to reach its checkpoint")
    }

    func testWarmupAndListenShareHandshakeAndWaitForActualReadiness() async throws {
        let socket = FakeSpeechSocket()
        let service = makeService([socket])
        var readyCount = 0
        service.onSessionReady = { readyCount += 1 }
        let warmup = Task { try await service.connect() }
        await waitFor { socket.receiver != nil }
        let listen = Task { try await service.connect() }
        await Task.yield()
        XCTAssertTrue(service.isConnecting)
        XCTAssertFalse(service.isSessionReady)
        await service.sendAudio(Data([0, 0]))
        XCTAssertEqual(socket.sends, 0, "No speech submitted before session_started")
        socket.emit(#"{"message_type":"session_started"}"#)
        try await warmup.value
        try await listen.value
        XCTAssertTrue(service.isSessionReady)
        XCTAssertFalse(service.isConnecting)
        XCTAssertEqual(readyCount, 1)
        await service.sendAudio(Data([0, 0]))
        XCTAssertEqual(socket.sends, 1)
        service.disconnect(); socket.finish()
    }

    func testMissingSessionStartedTimesOutAndClosesSocket() async {
        let socket = FakeSpeechSocket()
        let service = makeService([socket], timeout: 0.03)
        do { try await service.connect(); XCTFail("Must await actual provider readiness") } catch { }
        XCTAssertFalse(service.isConnected)
        XCTAssertFalse(service.isConnecting)
        XCTAssertEqual(socket.state, .completed)
        socket.finish()
    }

    func testCloseDuringHandshakeCannotReadyOrErrorNewConnection() async throws {
        let old = FakeSpeechSocket(), fresh = FakeSpeechSocket()
        let service = makeService([old, fresh])
        var errors = 0
        service.onError = { _ in errors += 1 }
        let first = Task { try await service.connect() }
        await waitFor { old.receiver != nil }
        service.disconnect()
        let next = Task { try await service.connect() }
        await waitFor { fresh.receiver != nil }
        old.emit(#"{"message_type":"session_started"}"#)
        await Task.yield()
        XCTAssertFalse(service.isSessionReady)
        fresh.emit(#"{"message_type":"session_started"}"#)
        try await next.value
        do { try await first.value; XCTFail("Closed setup should be cancelled") } catch { }
        XCTAssertTrue(service.isSessionReady)
        XCTAssertEqual(errors, 0)
        service.disconnect(); fresh.finish()
    }

    func testLateSendFailureCannotDisconnectReplacementSocket() async throws {
        let old = FakeSpeechSocket(), fresh = FakeSpeechSocket()
        let service = makeService([old, fresh])
        var errors = 0
        service.onError = { _ in errors += 1 }
        let first = Task { try await service.connect() }
        await waitFor { old.receiver != nil }
        old.emit(#"{"message_type":"session_started"}"#)
        try await first.value
        old.holdSend = true
        let sending = Task { await service.sendAudio(Data([0, 0])) }
        await waitFor { old.deferSendFailure != nil }
        service.disconnect(); old.finish()
        let next = Task { try await service.connect() }
        await waitFor { fresh.receiver != nil }
        fresh.emit(#"{"message_type":"session_started"}"#)
        try await next.value
        old.deferSendFailure?.resume(throwing: URLError(.networkConnectionLost))
        old.deferSendFailure = nil
        await sending.value
        XCTAssertTrue(service.isSessionReady)
        XCTAssertEqual(errors, 0)
        service.disconnect(); fresh.finish()
    }
}
