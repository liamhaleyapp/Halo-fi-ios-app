//
//  WebSocketManagerProtocol.swift
//  Halo-fi-IOS
//
//  Protocol for WebSocket manager operations.
//

import Foundation

/// Protocol defining common WebSocket manager operations.
/// Enables dependency injection and provides consistent interface.
@MainActor
protocol WebSocketManagerProtocol: AnyObject {
    /// Whether the WebSocket is currently connected
    var isConnected: Bool { get }

    /// Current connection status
    var connectionStatus: ConnectionStatus { get }

    /// Disconnects the WebSocket connection
    func disconnect()
}

/// Protocol for voice-specific WebSocket operations.
@MainActor
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
@MainActor
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

    /// Event stream — a new stream is created on each connect().
    /// Consumers iterate with `for await event in manager.events`.
    var events: AsyncStream<AgentEvent> { get }

    /// Connects to the agent WebSocket server.
    ///
    /// - Parameters:
    ///   - skipGreeting: When true, the backend bypasses
    ///     ``_send_initial_greeting`` so the user hears the answer
    ///     to their pre-prompt instead of "Good evening" first
    ///     (Phase 12).
    ///   - customGreetingId: When set (e.g. "deduction_intake"), the
    ///     backend sends a fixed canonical greeting instead of the
    ///     LLM-built welcome — used by entry points like the "Log
    ///     with voice" button on the Logged Deductions screen so
    ///     Halo opens with exactly the right question and no fake
    ///     priming user-message. Takes precedence over skipGreeting.
    func connect(skipGreeting: Bool, customGreetingId: String?) async throws

    /// Sends a message to the agent
    /// - Parameters:
    ///   - message: The message text
    ///   - context: Optional context data
    func sendMessage(_ message: String, context: [String: AnyCodable]?) async throws
}

extension AgentWebSocketManagerProtocol {
    /// Convenience overload — keeps existing zero-arg call sites
    /// working without forcing every caller to pass `skipGreeting:
    /// false`.
    func connect() async throws {
        try await connect(skipGreeting: false, customGreetingId: nil)
    }

    /// Backward-compat overload for callers that still pass only the
    /// skip flag (Phase 12 quick actions).
    func connect(skipGreeting: Bool) async throws {
        try await connect(skipGreeting: skipGreeting, customGreetingId: nil)
    }
}
