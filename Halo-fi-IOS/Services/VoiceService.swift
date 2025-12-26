//
//  VoiceService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/16/25.
//

import Foundation
import AVFoundation

@Observable
@MainActor
final class VoiceService: NSObject {
    static let shared = VoiceService()

    var isRecording = false
    var isPlaying = false

    // Forward connection state from WebSocketManager
    var isConnected: Bool { webSocketManager.isConnected }
    var connectionStatus: ConnectionStatus { webSocketManager.connectionStatus }

    private let webSocketManager = WebSocketManager.shared
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayer?
    private var recordingSession: AVAudioSession?

    private override init() {
        super.init()
        setupAudioSession()
    }

    // MARK: - Setup

    private func setupAudioSession() {
        do {
            recordingSession = AVAudioSession.sharedInstance()
            try recordingSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try recordingSession?.setActive(true)
        } catch {
            Logger.error("Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Connection Management

    func connect(userId: String) async throws {
        try await webSocketManager.connect(userId: userId)
        try await webSocketManager.sendVoiceStart()
    }

    func disconnect() {
        webSocketManager.disconnect()
    }

    // MARK: - Recording

    func startRecording() async throws {
        guard !isRecording else { return }

        guard PermissionManager.shared.isMicrophonePermissionGranted else {
            throw VoiceError.microphonePermissionDenied
        }

        // Ensure audio session is active before accessing input node
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            Logger.error("Failed to activate audio session: \(error)")
            throw VoiceError.audioEngineError
        }

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw VoiceError.audioEngineError
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Validate format has valid sample rate and channel count
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            Logger.error("Invalid audio format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) channels")
            throw VoiceError.audioEngineError
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            Task { @MainActor in
                await self?.processAudioBuffer(buffer)
            }
        }

        try audioEngine.start()
        isRecording = true
    }

    func stopRecording() {
        guard isRecording else { return }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard let audioData = bufferToData(buffer) else { return }

        do {
            try await webSocketManager.sendVoiceAudio(audioData)
        } catch {
            Logger.error("Failed to send audio data: \(error)")
        }
    }

    private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Convert float samples to 16-bit PCM
        let pcmData = samples.map { sample in
            Int16(max(-32768, min(32767, sample * 32768)))
        }

        return Data(bytes: pcmData, count: pcmData.count * MemoryLayout<Int16>.size)
    }

    // MARK: - Audio Playback

    func playAudioData(_ audioData: Data) async {
        guard !isPlaying else { return }

        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
        } catch {
            Logger.error("Failed to play audio: \(error)")
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
        }
    }
}

// MARK: - Voice Errors

enum VoiceError: LocalizedError {
    case audioEngineError
    case microphonePermissionDenied
    case recordingError
    case playbackError

    var errorDescription: String? {
        switch self {
        case .audioEngineError:
            return "Failed to initialize audio engine"
        case .microphonePermissionDenied:
            return "Microphone permission is required for voice chat"
        case .recordingError:
            return "Failed to record audio"
        case .playbackError:
            return "Failed to play audio"
        }
    }
}
