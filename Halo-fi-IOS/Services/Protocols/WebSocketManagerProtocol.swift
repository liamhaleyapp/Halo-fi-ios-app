//
//  WebSocketManagerProtocol.swift
//  Halo-fi-IOS
//
//  Protocol for WebSocket manager operations.
//

import Foundation

/// Protocol defining common WebSocket manager operations.
/// Enables dependency injection and provides consistent interface.
protocol WebSocketManagerProtocol: AnyObject {
    /// Whether the WebSocket is currently connected
    var isConnected: Bool { get }

    /// Current connection status
    var connectionStatus: ConnectionStatus { get }

    /// Disconnects the WebSocket connection
    func disconnect()
}

/// Protocol for voice-specific WebSocket operations.
protocol VoiceWebSocketManagerProtocol: WebSocketManagerProtocol {
    /// Connects to the voice WebSocket server
    /// - Parameter userId: The user ID for the session
    func connect(userId: String) async throws

    /// Sends a voice start message
    func sendVoiceStart() async throws

    /// Sends voice audio data
    /// - Parameter audioData: The audio data to send
    func sendVoiceAudio(_ audioData: Data) async throws

    /// Sends a voice end message
    func sendVoiceEnd() async throws

    /// Sends a ping message
    func sendPing() async throws
}

/// Protocol for agent chat WebSocket operations.
protocol AgentWebSocketManagerProtocol: WebSocketManagerProtocol {
    /// The last response from the agent
    var lastAgentResponse: String? { get }

    /// The last error message
    var lastError: String? { get }

    /// Current session ID from connection acknowledgment
    var currentSessionId: String? { get }

    /// Text being streamed from the agent
    var streamingText: String { get }

    /// Whether the agent is currently streaming a response
    var isStreaming: Bool { get }

    /// Connects to the agent WebSocket server
    func connect() async throws

    /// Sends a message to the agent
    /// - Parameters:
    ///   - message: The message text
    ///   - context: Optional context data
    func sendMessage(_ message: String, context: [String: AnyCodable]?) async throws
}
