import Foundation
import Testing
@testable import Halo_fi_IOS

struct VoiceAppActionTests {
    @Test func navigationKeepsTurnIdentityAndRejectsUnknownDestinations() throws {
        let data = Data(#"{"type":"app_action","turn_id":"turn-1","action":{"kind":"navigate","action_id":"turn-1","state":"proposed","target":"benefits","receipt":"Open benefits."}}"#.utf8)
        let decoded = try JSONDecoder().decode(AgentIncomingMessage.self, from: data)
        guard case .appAction(let payload) = decoded else { Issue.record("Expected navigation"); return }
        #expect(payload.turnId == "turn-1")
        #expect(payload.action.target == .benefits)
        let invalid = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "benefits", with: "external_url").utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AgentIncomingMessage.self, from: invalid) }
    }

    @Test @MainActor func badAudioReportsFailureWithoutSuccessfulCompletion() {
        let player = StreamingAudioPlayer()
        var failed = false
        var completed = false
        player.onPlaybackFailed = { failed = true }
        player.onPlaybackFinished = { completed = true }
        player.appendAudioChunk(Data("invalid mp3 fixture".utf8).base64EncodedString())
        player.playAccumulatedAudio(isFinal: true, turnId: "t")
        #expect(failed)
        #expect(!completed)
        #expect(!player.isPlaying)
        player.appendAudioChunk(Data("late audio".utf8).base64EncodedString())
        #expect(!player.isBuffering)
    }
}

@Test @MainActor func malformedOrExcessiveAudioFailsOnceAndDiscardsRemainder() {
    for oversized in [false, true] {
        let player = StreamingAudioPlayer()
        var failures = 0
        var completions = 0
        player.onPlaybackFailed = { failures += 1 }
        player.onPlaybackFinished = { completions += 1 }
        if oversized {
            let chunk = Data(repeating: 1, count: 3 * 1024 * 1024).base64EncodedString()
            player.appendAudioChunk(chunk)
            player.appendAudioChunk(chunk)
        } else {
            player.appendAudioChunk("not base64!")
        }
        player.appendAudioChunk(Data([1, 2, 3]).base64EncodedString())
        player.playAccumulatedAudio()
        #expect(failures == 1)
        #expect(completions == 0)
        #expect(!player.isBuffering)
    }
}

@Test func connectionDiagnosticsIdentifyLegacyAndRepairedBackend() throws {
    let old = try JSONDecoder().decode(ConnectionAckPayload.self,
        from: Data(#"{"type":"connection_ack","message":"Connected"}"#.utf8))
    let repaired = try JSONDecoder().decode(ConnectionAckPayload.self,
        from: Data(#"{"type":"connection_ack","message":"Connected","pipeline_revision":"voice-2026-09-08-r2"}"#.utf8))
    #expect(old.pipelineRevision == nil)
    #expect(repaired.pipelineRevision == "voice-2026-09-08-r2")
}


@Test @MainActor func legacyTextCompletionWithoutAudioReportsFailureOnce() throws {
    let player = StreamingAudioPlayer()
    var failures = 0
    var completions = 0
    player.onPlaybackFailed = { failures += 1 }
    player.onPlaybackFinished = { completions += 1 }
    // The exact protocol shape emitted by production after quota failures.
    let terminal = try JSONDecoder().decode(AudioCompletePayload.self,
        from: Data(#"{"type":"audio_complete","turn_id":"silent","message":"Here is your answer.","data":{"session_id":"s","voice_speed":1.0}}"#.utf8))
    player.resumeAcceptingChunks()
    player.playAccumulatedAudio(isFinal: true, turnId: terminal.turnId, isAcknowledgment: terminal.isAck)
    player.playAccumulatedAudio(isFinal: true, turnId: terminal.turnId)
    #expect(failures == 1)
    #expect(completions == 0)
    #expect(!player.isPlaying)
}

@Test @MainActor func missingAudioReachesCoordinatorErrorAndKeepsAnswerInChat() throws {
    let coordinator = ConversationCoordinator()
    // This is a completed reply, not the hands-free greeting credential handshake.
    coordinator.setConversationMode(.pushToTalk)
    let player = StreamingAudioPlayer()
    coordinator.configure(streamingAudioPlayer: player, audioFeedback: AudioFeedbackService(),
                          transcriptStore: ConversationTranscriptStore())
    // Exercise the actual decoded-event -> player -> coordinator callback path.
    var finals: [String] = []
    coordinator.onEvent = { event in
        if case .agentTextFinal(_, let text, _) = event { finals.append(text) }
    }
    let terminal = try JSONDecoder().decode(AudioCompletePayload.self,
        from: Data(#"{"type":"audio_complete","message":"The original answer.","data":{"session_id":"s"}}"#.utf8))
    coordinator.handleAgentEvent(.audioComplete(terminal))
    guard case .error = coordinator.state else {
        Issue.record("A silent final reply must leave processing with an explicit error")
        coordinator.disconnect()
        return
    }
    #expect(finals.contains("The original answer."))
    #expect(finals.contains { $0.contains("Voice audio is unavailable") })
    coordinator.disconnect()
}

@Test @MainActor func acknowledgmentAudioDoesNotCountAsTheAnswer() {
    let player = StreamingAudioPlayer()
    var failures = 0
    player.onPlaybackFailed = { failures += 1 }
    player.appendAudioChunk(silentWaveFixture().base64EncodedString())
    player.playAccumulatedAudio(isFinal: false, turnId: "t", isAcknowledgment: true)
    #expect(player.isPlaying)
    player.playAccumulatedAudio(isFinal: true, turnId: "t")
    #expect(failures == 1)
    #expect(!player.isPlaying)
}

@Test @MainActor func drainedSentenceAllowsEmptyFinalButNotNextSilentTurn() async throws {
    let player = StreamingAudioPlayer()
    var failures = 0
    var completions = 0
    player.onPlaybackFailed = { failures += 1 }
    player.onPlaybackFinished = { completions += 1 }
    player.appendAudioChunk(silentWaveFixture().base64EncodedString())
    player.playAccumulatedAudio(isFinal: false, turnId: "t")
    #expect(player.isPlaying)
    for _ in 0..<50 {
        if !player.isPlaying { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(!player.isPlaying)
    #expect(completions == 0)
    player.playAccumulatedAudio(isFinal: true, turnId: "t")
    #expect(completions == 1)
    #expect(failures == 0)
    player.resumeAcceptingChunks()
    player.playAccumulatedAudio(isFinal: true, turnId: "next")
    #expect(failures == 1)
    #expect(completions == 1)
}

@Test @MainActor func mutedAndAbandonedTurnsDoNotReportMissingAudio() {
    let player = StreamingAudioPlayer()
    var failures = 0
    player.onPlaybackFailed = { failures += 1 }
    player.setMuted(true)
    player.playAccumulatedAudio(isFinal: true)
    player.setMuted(false)
    player.stopAndDiscardPending()
    player.playAccumulatedAudio(isFinal: true)
    #expect(failures == 0)
}

/// 100 ms PCM WAV exercises the real AVAudioPlayer lifecycle without a provider.
private func silentWaveFixture() -> Data {
    var data = Data()
    func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
    func little(_ value: UInt32, bytes: Int) {
        for i in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (i * 8))) }
    }
    ascii("RIFF"); little(1636, bytes: 4); ascii("WAVEfmt ")
    little(16, bytes: 4); little(1, bytes: 2); little(1, bytes: 2)
    little(8000, bytes: 4); little(16000, bytes: 4); little(2, bytes: 2); little(16, bytes: 2)
    ascii("data"); little(1600, bytes: 4)
    data.append(Data(repeating: 0, count: 1600))
    return data
}
