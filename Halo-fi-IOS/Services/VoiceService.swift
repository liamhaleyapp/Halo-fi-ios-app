//
//  VoiceService.swift
//  Halo-fi-IOS
//
//  Audio capture service for voice input.
//  Captures microphone audio and emits buffers via callback.
//  Does not handle network - that's ElevenLabsSTTService's job.
//

import Foundation
import AVFoundation
import UIKit

@Observable
@MainActor
final class VoiceService: NSObject {
    static let shared = VoiceService()

    var isRecording = false
    var isPlaying = false

    /// Callback for audio buffers - set by external consumer (e.g., ElevenLabsSTTService)
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

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
            try recordingSession?.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers, .duckOthers])
            try recordingSession?.setActive(true)
        } catch {
            Logger.error("Failed to setup audio session: \(error)")
        }
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
            // Use .measurement mode when VoiceOver is running to avoid echo cancellation
            // filtering out VoiceOver's synthesized speech. Keep .voiceChat for non-VO users.
            let mode: AVAudioSession.Mode = UIAccessibility.isVoiceOverRunning ? .measurement : .voiceChat
            try session.setCategory(.playAndRecord, mode: mode, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers, .duckOthers])
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

        Logger.info("VoiceService: Starting recording at \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) channels")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            Task { @MainActor in
                self?.handleAudioBuffer(buffer)
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

        Logger.info("VoiceService: Stopped recording")
    }

    // MARK: - Audio Buffer Handling

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Emit buffer to callback (for ElevenLabsSTTService or other consumers)
        onAudioBuffer?(buffer)
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
