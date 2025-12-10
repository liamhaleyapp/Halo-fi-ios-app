//
//  WebSocketManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/16/25.
//

import Foundation
import Network

@MainActor
class WebSocketManager: ObservableObject {
    static let shared = WebSocketManager()
    
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    private var webSocketConnection: WebSocketConnection<VoiceIncomingMessage, VoiceOutgoingMessage>?
    private let baseURL = "wss://halofiapp-production.up.railway.app/ws/voice"
    private var sessionId: String = ""
    private var userId: String = ""
    
    private init() {}
    
    // MARK: - Connection Management
    
    func connect(userId: String) async throws {
        self.userId = userId
        self.sessionId = UUID().uuidString
        
        guard let url = URL(string: baseURL) else {
            throw WebSocketConnectionError.connectionError
        }
        
        let webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketConnection = WebSocketConnection<VoiceIncomingMessage, VoiceOutgoingMessage>(
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
            print("WebSocket listening error: \(error)")
            await MainActor.run {
                connectionStatus = .disconnected
                isConnected = false
            }
        }
    }
    
    private func handleIncomingMessage(_ message: VoiceIncomingMessage) async {
        switch message {
        case .response(let response):
            await handleVoiceResponse(response)
        case .error(let error):
            await handleVoiceError(error)
        case .pong(let pong):
            await handlePong(pong)
        }
    }
    
    private func handleVoiceResponse(_ response: VoiceResponseMessage) async {
        // Handle AI voice response
        print("Received voice response: \(response)")
        
        // TODO: Play audio response if audioData is present
        if let audioDataString = response.audioData,
           let audioData = Data(base64Encoded: audioDataString) {
            // Play the audio response
            await playAudioData(audioData)
        }
        
        // TODO: Update UI with text response if present
        if let text = response.text {
            print("AI Response: \(text)")
        }
    }
    
    private func handleVoiceError(_ error: VoiceErrorMessage) async {
        print("Voice error: \(error.error) (Code: \(error.code))")
        // TODO: Handle error appropriately
    }
    
    private func handlePong(_ pong: VoicePongMessage) async {
        print("Received pong: \(pong.timestamp)")
    }
    
    // MARK: - Audio Handling
    
    private func playAudioData(_ audioData: Data) async {
        // TODO: Implement audio playback
        print("Playing audio data of size: \(audioData.count) bytes")
    }
    
    // MARK: - Sending Messages
    
    func sendVoiceStart() async throws {
        guard let connection = webSocketConnection else {
            throw WebSocketConnectionError.disconnected
        }
        
        let message = VoiceStartMessage(sessionId: sessionId, userId: userId)
        try await connection.send(.start(message))
    }
    
    func sendVoiceAudio(_ audioData: Data) async throws {
        guard let connection = webSocketConnection else {
            throw WebSocketConnectionError.disconnected
        }
        
        let message = VoiceAudioMessage(sessionId: sessionId, audioData: audioData)
        try await connection.send(.audio(message))
    }
    
    func sendVoiceEnd() async throws {
        guard let connection = webSocketConnection else {
            throw WebSocketConnectionError.disconnected
        }
        
        let message = VoiceEndMessage(sessionId: sessionId)
        try await connection.send(.end(message))
    }
    
    func sendPing() async throws {
        guard let connection = webSocketConnection else {
            throw WebSocketConnectionError.disconnected
        }
        
        let message = VoicePingMessage()
        try await connection.send(.ping(message))
    }
}
