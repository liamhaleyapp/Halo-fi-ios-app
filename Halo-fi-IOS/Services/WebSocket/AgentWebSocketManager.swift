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

    // MARK: - Internal State Machine

    /// Single source of truth for connection lifecycle.
    /// Replaces the previous boolean flags (isConnected, isReconnecting, intentionalDisconnect).
    private enum InternalState {
        case disconnected
        case connecting(generation: UInt64)
        case connected(generation: UInt64)
        case reconnecting(generation: UInt64, attempt: Int)
        case disconnectedIntentionally
    }

    private var internalState: InternalState = .disconnected {
        didSet { syncDerivedState() }
    }

    /// Monotonically increasing counter — each connect() bumps this.
    /// Stale listeners compare their captured generation to bail out.
    private var generation: UInt64 = 0

    // MARK: - Derived UI Properties (driven by internalState)

    /// These stored properties exist because @Observable tracks stored property
    /// access but cannot track dependencies of computed properties on private state.
    private(set) var isConnected = false
    private(set) var connectionStatus: ConnectionStatus = .disconnected
    private(set) var isReconnecting = false

    private func syncDerivedState() {
        switch internalState {
        case .connected:
            isConnected = true
            connectionStatus = .connected
            isReconnecting = false
        case .connecting:
            isConnected = false
            connectionStatus = .pending
            isReconnecting = false
        case .reconnecting:
            isConnected = false
            connectionStatus = .reconnecting
            isReconnecting = true
        case .disconnected, .disconnectedIntentionally:
            isConnected = false
            connectionStatus = .disconnected
            isReconnecting = false
        }
    }

    // MARK: - Public Observable State

    var lastAgentResponse: String?
    var lastError: String?
    var currentSessionId: String?
    var streamingText: String = ""
    var isStreaming: Bool = false
    var connectionAckMessage: String?

    // MARK: - Event Stream

    /// The event stream. A new stream is created on each connect().
    /// ConversationCoordinator consumes this via `for await event in manager.events`.
    private(set) var events: AsyncStream<AgentEvent> = AsyncStream { $0.finish() }
    private var eventContinuation: AsyncStream<AgentEvent>.Continuation?

    // MARK: - Private State

    private var webSocketConnection: WebSocketConnection<AgentIncomingMessage, ClientMessagePayload>?
    private let baseURL = "wss://halofiapp-production.up.railway.app"
    private let tokenStorage: TokenStorageProtocol
    private var sessionId: String?
    private var concurrentSessionRetries = 0
    private let maxConcurrentSessionRetries = 3
    private let maxReconnectAttempts = 5

    /// Cumulative reconnect attempts across the current connect() session.
    /// Reset only by an explicit user-initiated connect() OR by a connection
    /// that survives `stableConnectionThreshold` without error. The previous
    /// implementation reset on every "Reconnected successfully" — but a
    /// successful TCP connect that immediately drops at the application
    /// layer would loop forever because each transient reconnect re-entered
    /// the for-loop at attempt 1.
    private var cumulativeReconnectAttempts = 0
    private var listenPhaseStartTime: Date?
    private let stableConnectionThreshold: TimeInterval = 10

    /// The single listener task. Cancelled on disconnect, replaced on connect.
    private var listenerTask: Task<Void, Never>?

    /// Phase 12 — set by quick-action button flows that send a
    /// pre-prompt the moment the WS opens. Persisted so auto-
    /// reconnects after a dropped connection keep the same
    /// behavior (no surprise greeting mid-conversation).
    private var skipInitialGreeting: Bool = false

    // MARK: - Init

    private init(tokenStorage: TokenStorageProtocol = TokenStorage()) {
        self.tokenStorage = tokenStorage
    }

    // MARK: - Connection Management

    func connect(skipGreeting: Bool = false) async throws {
        guard let accessToken = tokenStorage.getAccessToken() else {
            Logger.error("AgentWebSocket: Missing access token")
            throw AgentWebSocketError.missingToken
        }

        // Tear down any existing connection cleanly
        listenerTask?.cancel()
        listenerTask = nil
        webSocketConnection?.close()
        webSocketConnection = nil
        eventContinuation?.finish()

        // Bump generation so any surviving stale work exits
        generation += 1
        let currentGen = generation
        concurrentSessionRetries = 0
        cumulativeReconnectAttempts = 0

        // Persist skip-greeting for auto-reconnect parity (Phase 12).
        skipInitialGreeting = skipGreeting

        // Create session ID for this connection
        sessionId = UUID().uuidString

        // Build WebSocket URL with token as query parameter
        var urlComponents = URLComponents(string: "\(baseURL)/agent/ws")
        var items = [URLQueryItem(name: "token", value: accessToken)]
        if skipGreeting {
            items.append(URLQueryItem(name: "skip_greeting", value: "true"))
        }
        urlComponents?.queryItems = items

        guard let url = urlComponents?.url else {
            Logger.error("AgentWebSocket: Invalid URL")
            throw AgentWebSocketError.invalidURL
        }

        Logger.info("AgentWebSocket: Connecting to \(baseURL)/agent/ws")

        // Create WebSocket connection
        let webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketConnection = WebSocketConnection<AgentIncomingMessage, ClientMessagePayload>(
            webSocketTask: webSocketTask
        )

        // Create fresh event stream
        let (stream, continuation) = AsyncStream<AgentEvent>.makeStream()
        events = stream
        eventContinuation = continuation

        // Update state
        internalState = .connecting(generation: currentGen)

        Logger.info("AgentWebSocket: Connection initiated, starting listener")

        // Start the listener task (structured — stored and cancellable)
        listenerTask = Task { [weak self] in
            await self?.listenLoop(generation: currentGen)
        }
    }

    func disconnect() {
        Logger.info("AgentWebSocket: Disconnecting")

        internalState = .disconnectedIntentionally

        listenerTask?.cancel()
        listenerTask = nil
        webSocketConnection?.close()
        webSocketConnection = nil
        sessionId = nil
        currentSessionId = nil

        eventContinuation?.finish()
        eventContinuation = nil
    }

    // MARK: - Listener Loop (two-phase: listen + reconnect)

    /// Phase 1: Listen for incoming messages until the connection drops or is replaced.
    /// Phase 2: If the connection drops unexpectedly, attempt iterative reconnection.
    private func listenLoop(generation gen: UInt64) async {
        // === Phase 1: Listen ===
        await listenPhase(generation: gen)

        // === Phase 2: Reconnect (only if still current and not intentional) ===
        guard isCurrentGeneration(gen) else {
            Logger.info("AgentWebSocket: Listener exiting (stale generation)")
            return
        }
        guard !isIntentionallyDisconnected() else {
            Logger.info("AgentWebSocket: Listener ended (intentional disconnect)")
            return
        }

        await reconnectPhase(generation: gen)
    }

    /// Listens for messages on the current connection until it errors or is replaced.
    private func listenPhase(generation gen: UInt64) async {
        guard let connection = webSocketConnection else { return }

        // Track when the listen phase actually started so reconnectPhase
        // can decide whether the previous "successful reconnect" was
        // stable enough to reset the cumulative counter.
        listenPhaseStartTime = Date()

        do {
            while !Task.isCancelled {
                guard isCurrentGeneration(gen) else {
                    Logger.info("AgentWebSocket: Listener exiting (connection replaced)")
                    return
                }
                let message = try await connection.receive()
                guard isCurrentGeneration(gen) else {
                    Logger.info("AgentWebSocket: Listener exiting (connection replaced after receive)")
                    return
                }
                handleIncomingMessage(message, generation: gen)
            }
        } catch is CancellationError {
            Logger.info("AgentWebSocket: Listener cancelled")
        } catch {
            // Connection dropped — check if we should reconnect
            guard isCurrentGeneration(gen) else {
                Logger.info("AgentWebSocket: Listener ended (stale connection)")
                return
            }
            guard !isIntentionallyDisconnected() else {
                Logger.info("AgentWebSocket: Listener ended (intentional disconnect)")
                return
            }
            Logger.error("AgentWebSocket: Listening error: \(error.localizedDescription)")
            isConnected = false
        }
    }

    /// Iterative reconnection with exponential backoff.
    ///
    /// Cumulative attempt count: persists across reconnect→listen→drop
    /// cycles, so if the connection accepts then immediately closes
    /// (auth reject, server error mid-handshake), we still hit the cap
    /// and stop. The previous version reset the counter every time
    /// performReconnect succeeded, which meant a connection that died
    /// within milliseconds spun the attempt counter back to 1 and
    /// looped forever.
    ///
    /// Recovery: a connection that survives stableConnectionThreshold
    /// (10s) is considered healthy and the cumulative count is reset.
    private func reconnectPhase(generation gen: UInt64) async {
        // If the previous listen phase ran long enough to be considered
        // a stable connection, treat the upcoming reconnect cycle as a
        // fresh start. Otherwise the failure is part of the same
        // unhealthy session and counts toward the cap.
        if let started = listenPhaseStartTime,
           Date().timeIntervalSince(started) >= stableConnectionThreshold {
            Logger.info("AgentWebSocket: Previous connection was stable — resetting reconnect counter")
            cumulativeReconnectAttempts = 0
        }
        listenPhaseStartTime = nil

        while cumulativeReconnectAttempts < maxReconnectAttempts {
            guard !Task.isCancelled, isCurrentGeneration(gen) else { return }
            guard !isIntentionallyDisconnected() else { return }

            cumulativeReconnectAttempts += 1
            let attempt = cumulativeReconnectAttempts
            internalState = .reconnecting(generation: gen, attempt: attempt)

            // Announce for VoiceOver
            UIAccessibility.post(
                notification: .announcement,
                argument: "Connection lost. Reconnecting..."
            )

            // Exponential backoff: 1s, 2s, 4s, 8s, 16s
            let delay = pow(2.0, Double(attempt - 1))
            Logger.info("AgentWebSocket: Reconnecting in \(delay)s (attempt \(attempt)/\(maxReconnectAttempts))")

            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled, isCurrentGeneration(gen) else { return }
            guard !isIntentionallyDisconnected() else { return }

            // Clean up old connection
            webSocketConnection?.close()
            webSocketConnection = nil

            do {
                try await performReconnect(generation: gen)
                Logger.info("AgentWebSocket: Reconnected successfully")
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Reconnected. You can continue your conversation."
                )
                // Re-enter listen phase with the same generation. If it
                // survives stableConnectionThreshold, the next call to
                // reconnectPhase will reset cumulativeReconnectAttempts.
                await listenLoop(generation: gen)
                return
            } catch {
                Logger.error("AgentWebSocket: Reconnect attempt \(attempt) failed: \(error.localizedDescription)")
                // Loop continues to next attempt
            }
        }

        // All attempts exhausted
        guard isCurrentGeneration(gen) else { return }
        Logger.error("AgentWebSocket: Max reconnect attempts (\(maxReconnectAttempts)) reached")
        internalState = .disconnected
        lastError = "Connection lost. Please go back and try again."
        eventContinuation?.yield(.permanentDisconnect)
        eventContinuation?.finish()
    }

    /// Creates a new WebSocket connection for reconnection (does not bump generation).
    private func performReconnect(generation gen: UInt64) async throws {
        guard let accessToken = tokenStorage.getAccessToken() else {
            throw AgentWebSocketError.missingToken
        }

        var urlComponents = URLComponents(string: "\(baseURL)/agent/ws")
        var items = [URLQueryItem(name: "token", value: accessToken)]
        if skipInitialGreeting {
            // Reconnects honor the original skip flag so a dropped
            // mid-conversation socket doesn't suddenly play "Good
            // evening!" when it comes back.
            items.append(URLQueryItem(name: "skip_greeting", value: "true"))
        }
        urlComponents?.queryItems = items

        guard let url = urlComponents?.url else {
            throw AgentWebSocketError.invalidURL
        }

        let webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketConnection = WebSocketConnection<AgentIncomingMessage, ClientMessagePayload>(
            webSocketTask: webSocketTask
        )
        // State remains .reconnecting until connection_ack arrives
    }

    // MARK: - Generation & State Helpers

    private func isCurrentGeneration(_ gen: UInt64) -> Bool {
        switch internalState {
        case .connecting(let g), .connected(let g):
            return g == gen
        case .reconnecting(let g, _):
            return g == gen
        case .disconnected, .disconnectedIntentionally:
            return false
        }
    }

    private func isIntentionallyDisconnected() -> Bool {
        if case .disconnectedIntentionally = internalState { return true }
        return false
    }

    // MARK: - Message Handling

    private func handleIncomingMessage(_ message: AgentIncomingMessage, generation gen: UInt64) {
        switch message {
        case .connectionAck(let ack):
            handleConnectionAck(ack, generation: gen)
        case .streamChunk(let chunk):
            handleStreamChunk(chunk)
        case .agentResponse(let response):
            handleAgentResponse(response)
        case .error(let error):
            handleError(error)
        case .acknowledgment(let ack):
            Logger.info("Agent acknowledgment: \(ack.text ?? "no text")")
            eventContinuation?.yield(.acknowledgment(ack))
        case .audioChunk(let chunk):
            Logger.debug("Audio chunk received: \(chunk.audio.count) base64 chars")
            eventContinuation?.yield(.audioChunk(chunk))
        case .audioComplete(let complete):
            Logger.info("Audio complete. Text: \(complete.responseText.prefix(80))...")
            eventContinuation?.yield(.audioComplete(complete))
        case .voiceStatus(let payload):
            Logger.info("Voice status: \(payload.text)")
            eventContinuation?.yield(.voiceStatus(payload))
        case .unknown(let type):
            Logger.warning("AgentWebSocket: Unknown message type: \(type)")
        }
    }

    private func handleConnectionAck(_ ack: ConnectionAckPayload, generation gen: UInt64) {
        concurrentSessionRetries = 0
        internalState = .connected(generation: gen)
        currentSessionId = ack.connectionId ?? ack.sessionId
        connectionAckMessage = "\(ack.message) - Session: \(currentSessionId ?? "none")"
        Logger.info("Connection acknowledged: \(ack.message)")
        if let connectionId = ack.connectionId {
            Logger.debug("Connection ID: \(connectionId)")
        }
        if let userId = ack.userId {
            Logger.debug("User ID: \(userId)")
        }
        eventContinuation?.yield(.connectionAck(ack))
    }

    private func handleStreamChunk(_ chunk: StreamChunkPayload) {
        isStreaming = true
        streamingText += chunk.chunk
        Logger.debug("Stream chunk: \(chunk.chunk)")
        eventContinuation?.yield(.streamChunk(chunk))

        if chunk.complete == true {
            isStreaming = false
            lastAgentResponse = streamingText
            streamingText = ""
            Logger.debug("Stream complete")
        }
    }

    private func handleAgentResponse(_ response: AgentResponsePayload) {
        isStreaming = false
        streamingText = ""
        lastAgentResponse = response.message
        Logger.info("Agent Response: \(response.message)")
        if let data = response.data {
            Logger.debug("Response data: \(data)")
        }
        eventContinuation?.yield(.agentResponse(response))
    }

    private func handleError(_ error: ErrorPayload) {
        // Auto-retry on concurrent session (previous session still closing)
        if error.code == "CONCURRENT_SESSION" && concurrentSessionRetries < maxConcurrentSessionRetries {
            concurrentSessionRetries += 1
            Logger.info("AgentWebSocket: Concurrent session detected, closing connection to trigger reconnect (attempt \(concurrentSessionRetries)/\(maxConcurrentSessionRetries))")
            // Yield the error so the coordinator knows what happened
            eventContinuation?.yield(.error(error))
            // Close connection — this causes receive() to throw,
            // which naturally falls through to the reconnect phase
            webSocketConnection?.close()
            webSocketConnection = nil
            return
        }

        lastError = "\(error.error) (Code: \(error.code))"
        Logger.error("Agent Error: \(error.error) (Code: \(error.code))")
        if let details = error.details {
            Logger.error("Error details: \(details)")
        }
        eventContinuation?.yield(.error(error))
    }

    // MARK: - Sending Messages

    func sendMessage(_ message: String, context: [String: AnyCodable]? = nil) async throws {
        guard let connection = webSocketConnection else {
            Logger.error("AgentWebSocket: Cannot send - not connected")
            throw AgentWebSocketError.disconnected
        }

        // Reset streaming state for new message
        streamingText = ""
        isStreaming = false

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
