import XCTest
@testable import Halo_fi_IOS

final class VoiceBargeInTests: XCTestCase {
    func testSustainedSpeechInterruptsWithoutWaitingForTranscript() {
        for duration in [0.01, 0.02, 0.04] {
            var detector = VoiceBargeInDetector()
            var elapsed = 0.0
            while elapsed < 0.40 {
                elapsed += duration
                if detector.observe(rms: 0.06, duration: duration) == .interrupt { break }
            }
            XCTAssertGreaterThanOrEqual(elapsed, 0.35)
            XCTAssertLessThanOrEqual(elapsed, 0.40)
        }
    }

    func testIsolatedSpikesAndQuietAudioCannotInterrupt() {
        var detector = VoiceBargeInDetector()
        for _ in 0..<30 {
            XCTAssertNotEqual(detector.observe(rms: 0.07, duration: 0.02), .interrupt)
            for _ in 0..<5 { XCTAssertNotEqual(detector.observe(rms: 0.001, duration: 0.02), .interrupt) }
        }
    }

    func testResetDoesNotCarrySpeechIntoAnotherTurn() {
        var detector = VoiceBargeInDetector()
        for _ in 0..<15 { _ = detector.observe(rms: 0.06, duration: 0.02) }
        detector.reset()
        XCTAssertNotEqual(detector.observe(rms: 0.06, duration: 0.02), .interrupt)
    }
}

final class VoiceInterruptionAudioTests: XCTestCase {
    func testDetectedSpeechKeepsItsOpeningInOrder() {
        var audio = VoiceInterruptionAudio<Int>()
        for n in 0..<100 { XCTAssertTrue(audio.append(n, duration: 0.02)) }
        audio.beginInterruption()
        for n in 100..<110 { XCTAssertTrue(audio.append(n, duration: 0.02)) }
        let captured = audio.takeInterruptedAudio()
        XCTAssertTrue(captured.contains(85), "Keep the first 350 ms used by speech detection")
        XCTAssertEqual(captured.last, 109)
        XCTAssertEqual(captured, captured.sorted())
        XCTAssertFalse(audio.isInterrupted)
        XCTAssertTrue(audio.takeInterruptedAudio().isEmpty)
    }

    func testOrdinaryPlaybackDoesNotBecomeNextUserUtterance() {
        var audio = VoiceInterruptionAudio<Int>()
        for n in 0..<100 { _ = audio.append(n, duration: 0.02) }
        XCTAssertTrue(audio.takeInterruptedAudio().isEmpty)
        audio.beginInterruption()
        XCTAssertTrue(audio.takeInterruptedAudio().isEmpty)
    }

    func testRecoveryOverflowRejectsInsteadOfLosingOpeningWords() {
        var audio = VoiceInterruptionAudio<Int>()
        audio.beginInterruption()
        XCTAssertTrue(audio.append(1, duration: 0.25))
        for n in 2...8 { XCTAssertTrue(audio.append(n, duration: 0.25)) }
        XCTAssertFalse(audio.append(9, duration: 0.01))
        XCTAssertEqual(audio.takeInterruptedAudio(), Array(1...8))
    }

    @MainActor func testExplicitInterruptionDiscardsQueuedAndLateAudioWithoutAutoResumeCallback() {
        let player = StreamingAudioPlayer()
        var finishes = 0
        var failures = 0
        player.onPlaybackFinished = { finishes += 1 }
        player.onPlaybackFailed = { failures += 1 }
        player.appendAudioChunk(Data([1, 2, 3]).base64EncodedString())
        XCTAssertTrue(player.isBuffering)
        player.stopAndDiscardPending(notify: false)
        player.appendAudioChunk(Data([4, 5, 6]).base64EncodedString())
        player.playAccumulatedAudio(isFinal: true, turnId: "cancelled")
        XCTAssertFalse(player.isBuffering)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(failures, 0)
    }
}

@MainActor
private final class InterruptionAgentSocket: AgentWebSocketManagerProtocol {
    var isConnected = true
    var connectionStatus: ConnectionStatus = .connected
    var lastAgentResponse: String?
    var lastError: String?
    var currentSessionId: String? = "interruption-test"
    var streamingText = ""
    var isStreaming = false
    let events = AsyncStream<AgentEvent> { _ in }
    var cancelled: [String] = []
    func connect(skipGreeting: Bool, customGreetingId: String?) async throws { isConnected = true }
    func disconnect() { isConnected = false }
    func sendMessage(_ message: String, context: [String: AnyCodable]?, turnId: String?, streamAudio: Bool, streamText: Bool) async throws {}
    func sendCancel(turnId: String) async throws { cancelled.append(turnId) }
}

@MainActor
final class ConversationInterruptionTests: XCTestCase {
    private func responseAudio() -> Data {
        var data = Data()
        func ascii(_ text: String) { data.append(contentsOf: text.utf8) }
        func number(_ value: UInt32, _ count: Int) {
            for i in 0..<count { data.append(UInt8(truncatingIfNeeded: value >> (i * 8))) }
        }
        // Five seconds of silent PCM exercises real playback and its queue.
        ascii("RIFF"); number(80036, 4); ascii("WAVEfmt ")
        number(16, 4); number(1, 2); number(1, 2); number(8000, 4)
        number(16000, 4); number(2, 2); number(16, 2)
        ascii("data"); number(80000, 4); data.append(Data(repeating: 0, count: 80000))
        return data
    }

    private func startAnswer(_ coordinator: ConversationCoordinator, _ player: StreamingAudioPlayer) async throws {
        coordinator.configure(streamingAudioPlayer: player, audioFeedback: AudioFeedbackService(),
                              transcriptStore: ConversationTranscriptStore())
        coordinator.setConversationMode(.handsFree)
        // Avoid warm-up/network work: decoding the ack only establishes a session.
        coordinator.setInteractionMode(.text)
        let ack = try JSONDecoder().decode(ConnectionAckPayload.self,
            from: Data(#"{"type":"connection_ack","message":"Connected","connection_id":"interruption-test"}"#.utf8))
        coordinator.handleAgentEvent(.connectionAck(ack))
        await coordinator.sendText("A test question")
        player.appendAudioChunk(responseAudio().base64EncodedString())
        player.playAccumulatedAudio(isFinal: true, turnId: coordinator.currentTurnId)
        XCTAssertEqual(coordinator.state, .speaking)
        XCTAssertTrue(player.isPlaying)
    }

    func testRecognitionFailureDuringPlaybackPreservesAnswerAndState() async throws {
        let socket = InterruptionAgentSocket()
        let recognition = ElevenLabsSTTService(networkService: MockNetworkService())
        let coordinator = ConversationCoordinator(agentWebSocket: socket, sttService: recognition)
        let player = StreamingAudioPlayer()
        try await startAnswer(coordinator, player)
        let turn = coordinator.currentTurnId
        recognition.onError?(URLError(.networkConnectionLost))
        XCTAssertEqual(coordinator.state, .speaking, "Recognition recovery must not flash the whole conversation red")
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(coordinator.currentTurnId, turn)
        XCTAssertTrue(socket.cancelled.isEmpty)
        coordinator.disconnect()
    }

    func testInterruptCancelsRealTurnWithoutCompetingPlaybackFinishedTransition() async throws {
        let socket = InterruptionAgentSocket()
        let coordinator = ConversationCoordinator(agentWebSocket: socket,
            sttService: ElevenLabsSTTService(networkService: MockNetworkService()))
        let player = StreamingAudioPlayer()
        try await startAnswer(coordinator, player)
        let turn = try XCTUnwrap(coordinator.currentTurnId)
        let originalFinish = player.onPlaybackFinished
        var callbacks = 0
        player.onPlaybackFinished = { callbacks += 1; originalFinish?() }
        coordinator.stopSpeaking()
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isBuffering)
        XCTAssertNil(coordinator.currentTurnId)
        XCTAssertEqual(callbacks, 0, "Interrupt owns input resumption; natural completion must not race it")
        player.appendAudioChunk(responseAudio().base64EncodedString())
        player.playAccumulatedAudio(isFinal: true, turnId: turn)
        XCTAssertFalse(player.isPlaying, "Late cancelled speech must not restart playback")
        await Task.yield()
        XCTAssertEqual(socket.cancelled, [turn])
        coordinator.disconnect()
    }
}
