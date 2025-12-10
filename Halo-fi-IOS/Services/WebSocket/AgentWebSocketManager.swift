//
//  AgentWebSocketManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/17/25.
//

import Foundation

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

    // Callbacks for handling different message types
    var onAgentResponse: ((AgentResponsePayload) -> Void)?
    var onStreamChunk: ((StreamChunkPayload) -> Void)?
    var onError: ((ErrorPayload) -> Void)?
    var onConnectionAck: ((ConnectionAckPayload) -> Void)?

    private init(tokenStorage: TokenStorageProtocol = TokenStorage()) {
        self.tokenStorage = tokenStorage
    }
    
    // MARK: - Connection Management
    
    func connect() async throws {
        guard let accessToken = tokenStorage.getAccessToken() else {
            throw AgentWebSocketError.missingToken
        }
        
        // Create session ID for this connection
        sessionId = UUID().uuidString
        
        // Build WebSocket URL with token as query parameter
        var urlComponents = URLComponents(string: "\(baseURL)/agent/ws")
        urlComponents?.queryItems = [URLQueryItem(name: "token", value: accessToken)]
        
        guard let url = urlComponents?.url else {
            throw AgentWebSocketError.invalidURL
        }
        
        let webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketConnection = WebSocketConnection<AgentIncomingMessage, ClientMessagePayload>(
            webSocketTask: webSocketTask
        )
        
        connectionStatus = .pending
        isConnected = true
        connectionStatus = .connected
        
        // Start listening for messages
        Task {
            await startListening()
        }
    }
    
    func disconnect() {
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
        } catch {
            Logger.error("Agent WebSocket listening error: \(error)")
            await MainActor.run {
                connectionStatus = .disconnected
                isConnected = false
                lastError = "Connection error: \(error.localizedDescription)"
            }
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
        await MainActor.run {
            lastError = "\(error.error) (Code: \(error.code))"
            Logger.error("Agent Error: \(error.error) (Code: \(error.code))")
            if let details = error.details {
                Logger.error("Error details: \(details)")
            }
        }
        onError?(error)
    }

    private func handleConnectionAck(_ ack: ConnectionAckPayload) async {
        await MainActor.run {
            currentSessionId = ack.sessionId
            connectionAckMessage = "\(ack.message) - Session: \(ack.sessionId ?? "none")"
            Logger.info("Connection acknowledged: \(ack.message)")
            if let sessionId = ack.sessionId {
                Logger.debug("Session ID: \(sessionId)")
            }
            if let userId = ack.userId {
                Logger.debug("User ID: \(userId)")
            }
        }
        onConnectionAck?(ack)
    }
    
    // MARK: - Sending Messages
    
    func sendMessage(_ message: String, context: [String: AnyCodable]? = nil) async throws {
        guard let connection = webSocketConnection else {
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
            sessionId: currentSessionId ?? sessionId
        )
        
        try await connection.send(payload)
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
