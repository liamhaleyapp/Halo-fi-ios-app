//
//  AgentWebSocketManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/17/25.
//

import Foundation
import UIKit

@Observable
@MainActor
final class AgentWebSocketManager: AgentWebSocketManagerProtocol {
    static let shared = AgentWebSocketManager()

    var isConnected = false
    var connectionStatus: ConnectionStatus = .disconnected
    var lastAgentResponse: String?
    var lastError: String?
    var currentSessionId: String?
    var streamingText: String = ""
    var isStreaming: Bool = false
    var connectionAckMessage: String?

    private var webSocketConnection: WebSocketConnection<AgentIncomingMessage, ClientMessagePayload>?
    private let baseURL = "wss://halofiapp-production.up.railway.app"
    private let tokenStorage: TokenStorageProtocol
    private var sessionId: String?
    private var concurrentSessionRetries = 0
    private let maxConcurrentSessionRetries = 3

    // Reconnection
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5
    private(set) var isReconnecting = false
    private var intentionalDisconnect = false

    /// Called when reconnection fails permanently
    var onPermanentDisconnect: (() -> Void)?

    // Callbacks for handling different message types
    var onAgentResponse: ((AgentResponsePayload) -> Void)?
    var onStreamChunk: ((StreamChunkPayload) -> Void)?
    var onError: ((ErrorPayload) -> Void)?
    var onConnectionAck: ((ConnectionAckPayload) -> Void)?
    var onAcknowledgment: ((AcknowledgmentPayload) -> Void)?
    var onAudioChunk: ((AudioChunkPayload) -> Void)?
    var onAudioComplete: ((AudioCompletePayload) -> Void)?

    private init(tokenStorage: TokenStorageProtocol = TokenStorage()) {
        self.tokenStorage = tokenStorage
    }
    
    // MARK: - Connection Management
    
    func connect() async throws {
        guard let accessToken = tokenStorage.getAccessToken() else {
            Logger.error("AgentWebSocket: Missing access token")
            throw AgentWebSocketError.missingToken
        }

        // Create session ID for this connection
        sessionId = UUID().uuidString

        // Build WebSocket URL with token as query parameter
        var urlComponents = URLComponents(string: "\(baseURL)/agent/ws")
        urlComponents?.queryItems = [URLQueryItem(name: "token", value: accessToken)]

        guard let url = urlComponents?.url else {
            Logger.error("AgentWebSocket: Invalid URL")
            throw AgentWebSocketError.invalidURL
        }

        Logger.info("AgentWebSocket: Connecting to \(baseURL)/agent/ws")

        let webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketConnection = WebSocketConnection<AgentIncomingMessage, ClientMessagePayload>(
            webSocketTask: webSocketTask
        )

        connectionStatus = .pending
        isConnected = true
        intentionalDisconnect = false

        Logger.info("AgentWebSocket: Connection initiated, starting listener")

        // Start listening for messages
        Task {
            await startListening()
        }
    }

    func disconnect() {
        Logger.info("AgentWebSocket: Disconnecting")
        intentionalDisconnect = true
        reconnectAttempt = 0
        isReconnecting = false
        webSocketConnection?.close()
        webSocketConnection = nil
        isConnected = false
        connectionStatus = .disconnected
        sessionId = nil
        currentSessionId = nil
    }
    
    // MARK: - Message Handling
    
    private func startListening() async {
        guard let connection = webSocketConnection else { return }
        
        do {
            while isConnected {
                let message = try await connection.receive()
                await handleIncomingMessage(message)
            }
        } catch is CancellationError {
            Logger.info("Agent WebSocket listener cancelled")
        } catch {
            // Ignore errors during intentional disconnect
            guard !intentionalDisconnect else {
                Logger.info("Agent WebSocket listener ended (intentional disconnect)")
                return
            }
            Logger.error("Agent WebSocket listening error: \(error.localizedDescription)")
            await MainActor.run {
                isConnected = false
            }
            // Attempt reconnection
            await attemptReconnect()
        }
    }
    
    private func handleIncomingMessage(_ message: AgentIncomingMessage) async {
        switch message {
        case .agentResponse(let response):
            await handleAgentResponse(response)
        case .streamChunk(let chunk):
            await handleStreamChunk(chunk)
        case .error(let error):
            await handleError(error)
        case .connectionAck(let ack):
            await handleConnectionAck(ack)
        case .acknowledgment(let ack):
            Logger.info("Agent acknowledgment: \(ack.text ?? "no text")")
            onAcknowledgment?(ack)
        case .audioChunk(let chunk):
            await handleAudioChunk(chunk)
        case .audioComplete(let complete):
            await handleAudioComplete(complete)
        case .unknown(let type):
            Logger.warning("AgentWebSocket: Unknown message type: \(type)")
        }
    }
    
    private func handleAgentResponse(_ response: AgentResponsePayload) async {
        await MainActor.run {
            isStreaming = false
            streamingText = ""
            lastAgentResponse = response.message
            Logger.info("Agent Response: \(response.message)")
            if let data = response.data {
                Logger.debug("Response data: \(data)")
            }
        }
        onAgentResponse?(response)
    }

    private func handleStreamChunk(_ chunk: StreamChunkPayload) async {
        await MainActor.run {
            isStreaming = true
            streamingText += chunk.chunk
            Logger.debug("Stream chunk: \(chunk.chunk)")
        }
        onStreamChunk?(chunk)

        // If this is the final chunk, we can process the complete message
        if chunk.complete == true {
            await MainActor.run {
                isStreaming = false
                lastAgentResponse = streamingText
                streamingText = ""
                Logger.debug("Stream complete")
            }
        }
    }

    private func handleError(_ error: ErrorPayload) async {
        // Auto-retry on concurrent session (previous session still closing)
        if error.code == "CONCURRENT_SESSION" && concurrentSessionRetries < maxConcurrentSessionRetries {
            concurrentSessionRetries += 1
            Logger.info("AgentWebSocket: Concurrent session detected, retrying in 1s (attempt \(concurrentSessionRetries)/\(maxConcurrentSessionRetries))")
            disconnect()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            try? await connect()
            return
        }

        await MainActor.run {
            lastError = "\(error.error) (Code: \(error.code))"
            Logger.error("Agent Error: \(error.error) (Code: \(error.code))")
            if let details = error.details {
                Logger.error("Error details: \(details)")
            }
        }
        onError?(error)
    }

    private func handleAudioChunk(_ chunk: AudioChunkPayload) async {
        Logger.debug("Audio chunk received: \(chunk.audio.count) base64 chars")
        onAudioChunk?(chunk)
    }

    private func handleAudioComplete(_ complete: AudioCompletePayload) async {
        Logger.info("Audio complete. Text: \(complete.responseText.prefix(80))...")
        onAudioComplete?(complete)
    }

    private func handleConnectionAck(_ ack: ConnectionAckPayload) async {
        concurrentSessionRetries = 0
        reconnectAttempt = 0
        isReconnecting = false
        await MainActor.run {
            connectionStatus = .connected
            // Use connectionId if available, fallback to sessionId
            currentSessionId = ack.connectionId ?? ack.sessionId
            connectionAckMessage = "\(ack.message) - Session: \(currentSessionId ?? "none")"
            Logger.info("Connection acknowledged: \(ack.message)")
            if let connectionId = ack.connectionId {
                Logger.debug("Connection ID: \(connectionId)")
            }
            if let userId = ack.userId {
                Logger.debug("User ID: \(userId)")
            }
        }
        onConnectionAck?(ack)
    }
    
    // MARK: - Reconnection

    private func attemptReconnect() async {
        guard !isReconnecting else { return }
        guard !intentionalDisconnect else { return }
        guard reconnectAttempt < maxReconnectAttempts else {
            Logger.error("AgentWebSocket: Max reconnect attempts (\(maxReconnectAttempts)) reached")
            await MainActor.run {
                connectionStatus = .disconnected
                lastError = "Connection lost. Please go back and try again."
                isReconnecting = false
            }
            onPermanentDisconnect?()
            return
        }

        isReconnecting = true
        reconnectAttempt += 1

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s
        let delay = pow(2.0, Double(reconnectAttempt - 1))
        Logger.info("AgentWebSocket: Reconnecting in \(delay)s (attempt \(reconnectAttempt)/\(maxReconnectAttempts))")

        await MainActor.run {
            connectionStatus = .reconnecting
        }

        // Announce for VoiceOver
        UIAccessibility.post(notification: .announcement, argument: "Connection lost. Reconnecting...")

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        // Check if user manually disconnected during the wait
        guard !intentionalDisconnect else {
            isReconnecting = false
            return
        }

        // Clean up old connection
        webSocketConnection?.close()
        webSocketConnection = nil

        do {
            try await connect()
            isReconnecting = false
            Logger.info("AgentWebSocket: Reconnected successfully")
            UIAccessibility.post(notification: .announcement, argument: "Reconnected. You can continue your conversation.")
        } catch {
            isReconnecting = false
            Logger.error("AgentWebSocket: Reconnect failed: \(error.localizedDescription)")
            // Try again with longer delay
            await attemptReconnect()
        }
    }

    // MARK: - Sending Messages
    
    func sendMessage(_ message: String, context: [String: AnyCodable]? = nil) async throws {
        guard let connection = webSocketConnection else {
            Logger.error("AgentWebSocket: Cannot send - not connected")
            throw AgentWebSocketError.disconnected
        }

        // Reset streaming state for new message
        await MainActor.run {
            streamingText = ""
            isStreaming = false
        }

        // Use the session ID from connection ack if available, otherwise use our generated one
        let payload = ClientMessagePayload(
            message: message,
            context: context,
            sessionId: currentSessionId ?? sessionId,
            streamAudio: true
        )

        Logger.info("AgentWebSocket: Sending message: '\(message)' with sessionId: \(payload.sessionId ?? "nil")")

        try await connection.send(payload)

        Logger.info("AgentWebSocket: Message sent successfully")
    }
}

// MARK: - Error Types

enum AgentWebSocketError: LocalizedError {
    case missingToken
    case invalidURL
    case disconnected
    case connectionError
    case encodingError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Access token is missing. Please log in first."
        case .invalidURL:
            return "Invalid WebSocket URL"
        case .disconnected:
            return "WebSocket is not connected"
        case .connectionError:
            return "Failed to establish WebSocket connection"
        case .encodingError:
            return "Failed to encode message"
        case .decodingError:
            return "Failed to decode message"
        }
    }
}
