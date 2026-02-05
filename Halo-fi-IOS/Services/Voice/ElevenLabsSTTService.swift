//
//  ElevenLabsSTTService.swift
//  Halo-fi-IOS
//
//  Real-time speech-to-text using ElevenLabs Scribe v2.
//
//  Responsibilities:
//  - Fetch STT token from backend
//  - Connect to ElevenLabs WebSocket
//  - Send audio chunks
//  - Emit transcription events
//

import Foundation
import AVFoundation

// MARK: - STT Errors

enum ElevenLabsSTTError: LocalizedError {
    case tokenFetchFailed(String)
    case connectionFailed(String)
    case notConnected
    case invalidAudioFormat

    var errorDescription: String? {
        switch self {
        case .tokenFetchFailed(let message):
            return "Failed to get voice credentials: \(message)"
        case .connectionFailed(let message):
            return "Voice connection failed: \(message)"
        case .notConnected:
            return "Voice service not connected"
        case .invalidAudioFormat:
            return "Invalid audio format"
        }
    }
}

// MARK: - STT Service

@Observable
@MainActor
final class ElevenLabsSTTService {
    // MARK: - Public State

    private(set) var isConnected = false
    private(set) var isConnecting = false

    // MARK: - Callbacks

    /// Called with transcription text and whether it's final (committed)
    var onTranscription: ((String, Bool) -> Void)?

    /// Called when an error occurs
    var onError: ((Error) -> Void)?

    /// Called when connection is established
    var onConnected: (() -> Void)?

    /// Called when connection is lost
    var onDisconnected: (() -> Void)?

    /// Called when session is ready to receive audio (session_started received)
    var onSessionReady: (() -> Void)?

    // MARK: - Private Properties

    private let networkService: NetworkServiceProtocol
    private var webSocketTask: URLSessionWebSocketTask?
    private var currentToken: STTTokenResponse?
    private var listeningTask: Task<Void, Never>?
    private var isSessionReady = false  // Wait for session_started before sending audio

    // Throttle updates to prevent UI jitter
    private var lastUpdateTime: Date = .distantPast
    private let updateThrottleInterval: TimeInterval = 0.15 // 150ms

    // MARK: - Initialization

    init(networkService: NetworkServiceProtocol = NetworkService.shared) {
        self.networkService = networkService
    }

    // MARK: - Public API

    /// Connect to ElevenLabs STT (fetches fresh token each time)
    func connect() async throws {
        guard !isConnected && !isConnecting else { return }

        isConnecting = true
        defer { isConnecting = false }

        // 1. Fetch token from backend
        do {
            currentToken = try await fetchSTTToken()
            if let config = currentToken?.config {
                Logger.info("ElevenLabsSTT: Token fetched - format: \(config.audioFormat), sampleRate: \(config.sampleRate), language: \(config.languageCode)")
            } else {
                Logger.info("ElevenLabsSTT: Token fetched (no config)")
            }
        } catch {
            Logger.error("ElevenLabsSTT: Token fetch failed: \(error)")
            throw ElevenLabsSTTError.tokenFetchFailed(error.localizedDescription)
        }

        guard let token = currentToken else {
            Logger.error("ElevenLabsSTT: No token received")
            throw ElevenLabsSTTError.tokenFetchFailed("No token received")
        }

        // 2. Connect to ElevenLabs WebSocket
        guard let url = URL(string: token.websocketUrl) else {
            throw ElevenLabsSTTError.connectionFailed("Invalid WebSocket URL")
        }

        // Add token to URL if needed (some APIs expect it as query param)
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = urlComponents?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "token", value: token.token))
        urlComponents?.queryItems = queryItems

        guard let finalURL = urlComponents?.url else {
            throw ElevenLabsSTTError.connectionFailed("Failed to build WebSocket URL")
        }

        // ElevenLabs uses token in query param, not Authorization header
        // Log URL without token for security
        Logger.info("ElevenLabsSTT: Connecting to \(url.host ?? "unknown")")

        var request = URLRequest(url: finalURL)
        request.timeoutInterval = 30

        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()

        isConnected = true
        isSessionReady = false  // Wait for session_started
        startListening()

        Logger.info("ElevenLabsSTT: WebSocket task started, waiting for session_started")
        onConnected?()
    }

    /// Disconnect from ElevenLabs STT
    func disconnect() {
        listeningTask?.cancel()
        listeningTask = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        isConnected = false
        isSessionReady = false
        currentToken = nil

        Logger.info("ElevenLabsSTT: Disconnected")
        onDisconnected?()
    }

    /// Send audio data to ElevenLabs for transcription
    func sendAudio(_ pcmData: Data) async {
        guard isConnected else {
            Logger.debug("ElevenLabsSTT: Skipping audio - not connected")
            return
        }

        guard isSessionReady else {
            // Still waiting for session_started - silently skip
            return
        }

        guard let task = webSocketTask else {
            Logger.warning("ElevenLabsSTT: WebSocket task is nil but isConnected=true")
            return
        }

        // Check WebSocket state
        let state = task.state
        guard state == .running else {
            Logger.warning("ElevenLabsSTT: WebSocket not running, state=\(state.rawValue)")
            return
        }

        do {
            // ElevenLabs expects audio wrapped in input_audio_chunk JSON message
            let audioBase64 = pcmData.base64EncodedString()
            let sampleRate = currentToken?.config.sampleRate ?? 16000

            let message: [String: Any] = [
                "message_type": "input_audio_chunk",
                "audio_base_64": audioBase64,
                "commit": false,
                "sample_rate": sampleRate
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: message)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                Logger.error("ElevenLabsSTT: Failed to encode audio message")
                return
            }

            try await task.send(.string(jsonString))
        } catch {
            Logger.error("ElevenLabsSTT: Failed to send audio (\(pcmData.count) bytes): \(error)")
            handleConnectionError(error)
        }
    }

    /// Send audio buffer from AVAudioEngine
    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameCount = Int(buffer.frameLength)
        let inputSampleRate = buffer.format.sampleRate
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Use sample rate from backend config, default to 16kHz
        let targetSampleRate = Double(currentToken?.config.sampleRate ?? 16000)
        let resampledSamples: [Float]

        if inputSampleRate != targetSampleRate {
            resampledSamples = resampleAudio(samples, from: inputSampleRate, to: targetSampleRate)
        } else {
            resampledSamples = samples
        }

        // Convert float samples to 16-bit PCM
        let pcmData = ElevenLabsAudioFrame.floatToPCM16(resampledSamples)

        await sendAudio(pcmData)
    }

    /// Resample audio using linear interpolation
    private func resampleAudio(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        guard inputRate != outputRate, !samples.isEmpty else { return samples }

        let ratio = inputRate / outputRate
        let outputLength = Int(Double(samples.count) / ratio)
        var output = [Float](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let srcIndex = Double(i) * ratio
            let srcIndexInt = Int(srcIndex)
            let fraction = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < samples.count {
                // Linear interpolation between two samples
                output[i] = samples[srcIndexInt] * (1 - fraction) + samples[srcIndexInt + 1] * fraction
            } else if srcIndexInt < samples.count {
                output[i] = samples[srcIndexInt]
            }
        }

        return output
    }

    // MARK: - Private Methods

    private func fetchSTTToken() async throws -> STTTokenResponse {
        return try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.Agent.sttToken,
            method: .POST,
            body: nil,
            responseType: STTTokenResponse.self
        )
    }

    private func startListening() {
        listeningTask = Task { [weak self] in
            guard let self = self else { return }

            Logger.debug("ElevenLabsSTT: Starting message receive loop")

            while !Task.isCancelled && self.isConnected {
                do {
                    guard let message = try await self.webSocketTask?.receive() else {
                        Logger.warning("ElevenLabsSTT: WebSocket task returned nil")
                        break
                    }

                    await MainActor.run {
                        self.handleMessage(message)
                    }
                } catch {
                    // Detailed error logging
                    let nsError = error as NSError
                    Logger.error("ElevenLabsSTT: Receive error - domain: \(nsError.domain), code: \(nsError.code), description: \(error.localizedDescription)")
                    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                        Logger.error("ElevenLabsSTT: Underlying error: \(underlyingError)")
                    }

                    if !Task.isCancelled {
                        await MainActor.run {
                            self.handleConnectionError(error)
                        }
                    }
                    break
                }
            }

            Logger.debug("ElevenLabsSTT: Message receive loop ended (isCancelled=\(Task.isCancelled), isConnected=\(self.isConnected))")
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleTextMessage(text)

        case .data(let data):
            // Binary messages (if any) - usually responses are JSON
            if let text = String(data: data, encoding: .utf8) {
                handleTextMessage(text)
            }

        @unknown default:
            Logger.warning("ElevenLabsSTT: Unknown message type")
        }
    }

    private func handleTextMessage(_ text: String) {
        let message = ElevenLabsIncomingMessage(from: text)

        switch message {
        case .transcript(let event):
            // Throttle partial updates to prevent jitter
            let now = Date()
            let isFinal = event.isCommitted
            if isFinal || now.timeIntervalSince(lastUpdateTime) >= updateThrottleInterval {
                lastUpdateTime = now
                Logger.debug("ElevenLabsSTT: Transcript (\(isFinal ? "final" : "partial")): \(event.text)")
                onTranscription?(event.text, isFinal)
            }

        case .error(let event):
            Logger.error("ElevenLabsSTT: Server error: \(event.error)")
            onError?(ElevenLabsSTTError.connectionFailed(event.error))

        case .sessionStarted:
            Logger.info("ElevenLabsSTT: Session started - ready to receive audio")
            // Config is already set via the token/URL - just start sending audio
            isSessionReady = true
            onSessionReady?()

        case .unknown(let rawText):
            // Log at info level to catch any unhandled server messages
            Logger.info("ElevenLabsSTT: Unhandled message type: \(rawText.prefix(500))")
        }
    }

    private func handleConnectionError(_ error: Error) {
        Logger.error("ElevenLabsSTT: Connection error: \(error)")

        // Log close code if available
        if let task = webSocketTask {
            Logger.error("ElevenLabsSTT: Close code: \(task.closeCode.rawValue)")
            if let reason = task.closeReason, let reasonStr = String(data: reason, encoding: .utf8) {
                Logger.error("ElevenLabsSTT: Close reason: \(reasonStr)")
            }
        }

        // Clean up connection state
        isConnected = false
        isSessionReady = false
        listeningTask?.cancel()
        listeningTask = nil
        webSocketTask = nil

        onError?(error)
        onDisconnected?()
    }

}
