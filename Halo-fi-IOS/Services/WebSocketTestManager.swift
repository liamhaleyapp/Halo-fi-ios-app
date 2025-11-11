//
//  WebSocketTestManager.swift
//  Halo-fi-IOS
//
//  Created for testing WebSocket integration with echo servers
//  COMPLETELY SEPARATE from production code - only compiled in DEBUG builds
//

import Foundation

#if DEBUG

// MARK: - Test Configuration

enum WebSocketTestServer: Hashable {
    case echoWebSocketOrg
    case postmanEcho
    case custom(String)
    
    var url: String {
        switch self {
        case .echoWebSocketOrg:
            return "wss://echo.websocket.org"
        case .postmanEcho:
            return "wss://ws.postman-echo.com/raw"
        case .custom(let url):
            return url
        }
    }
    
    var name: String {
        switch self {
        case .echoWebSocketOrg:
            return "Echo WebSocket.org"
        case .postmanEcho:
            return "Postman Echo"
        case .custom(let url):
            return "Custom: \(url)"
        }
    }
}

// MARK: - Test-Only WebSocket Connection Wrapper
// This is completely separate from production WebSocketConnection

private final class TestWebSocketConnection: NSObject, Sendable {
    private let webSocketTask: URLSessionWebSocketTask
    
    init(webSocketTask: URLSessionWebSocketTask) {
        self.webSocketTask = webSocketTask
        super.init()
        webSocketTask.resume()
    }
    
    deinit {
        webSocketTask.cancel(with: .goingAway, reason: nil)
    }
    
    func send(_ message: String) async throws {
        try await webSocketTask.send(.string(message))
    }
    
    func receive() async throws -> String {
        switch try await webSocketTask.receive() {
        case let .string(text):
            return text
        case let .data(data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw WebSocketConnectionError.decodingError
            }
            return text
        @unknown default:
            throw WebSocketConnectionError.decodingError
        }
    }
    
    func close() {
        webSocketTask.cancel(with: .goingAway, reason: nil)
    }
}

// MARK: - WebSocket Test Manager

@MainActor
class WebSocketTestManager: ObservableObject {
    static let shared = WebSocketTestManager()
    
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastReceivedMessage: String = ""
    @Published var testLogs: [String] = []
    
    private var webSocketConnection: TestWebSocketConnection?
    private var currentTestServer: WebSocketTestServer?
    
    private init() {}
    
    // MARK: - Test Connection Methods
    
    /// Connect to an echo server for testing
    func connectToEchoServer(_ server: WebSocketTestServer = .echoWebSocketOrg) async throws {
        currentTestServer = server
        addLog("🔌 Connecting to \(server.name)...")
        
        guard let url = URL(string: server.url) else {
            addLog("❌ Invalid URL: \(server.url)")
            throw WebSocketConnectionError.connectionError
        }
        
        let webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketConnection = TestWebSocketConnection(webSocketTask: webSocketTask)
        
        connectionStatus = .pending
        isConnected = true
        connectionStatus = .connected
        addLog("✅ Connected to \(server.name)")
        
        // Start listening for messages
        Task {
            await startListening()
        }
    }
    
    /// Disconnect from echo server
    func disconnect() {
        webSocketConnection?.close()
        webSocketConnection = nil
        isConnected = false
        connectionStatus = .disconnected
        addLog("🔌 Disconnected")
    }
    
    // MARK: - Test Message Handling
    
    private func startListening() async {
        guard let connection = webSocketConnection else { return }
        
        do {
            while isConnected {
                let message = try await connection.receive()
                await MainActor.run {
                    self.lastReceivedMessage = message
                    self.addLog("📥 Received: \(message.prefix(100))")
                }
            }
        } catch {
            addLog("❌ Listening error: \(error.localizedDescription)")
            await MainActor.run {
                connectionStatus = .disconnected
                isConnected = false
            }
        }
    }
    
    // MARK: - Test Send Methods
    
    /// Send a test message to echo server
    func sendTestMessage(_ message: String) async throws {
        guard let connection = webSocketConnection else {
            throw WebSocketConnectionError.disconnected
        }
        
        addLog("📤 Sending: \(message.prefix(100))")
        try await connection.send(message)
    }
    
    /// Send a JSON test message
    func sendJSONTestMessage(_ message: String) async throws {
        let jsonMessage = """
        {"message": "\(message)", "timestamp": \(Int64(Date().timeIntervalSince1970 * 1000))}
        """
        try await sendTestMessage(jsonMessage)
    }
    
    /// Test sending your actual VoiceStartMessage format (will be echoed back)
    func testVoiceStartMessage(sessionId: String, userId: String) async throws {
        guard let connection = webSocketConnection else {
            throw WebSocketConnectionError.disconnected
        }
        
        let testMessage = VoiceStartMessage(sessionId: sessionId, userId: userId)
        let encoder = JSONEncoder()
        
        do {
            let jsonData = try encoder.encode(testMessage)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                addLog("📤 Testing VoiceStartMessage format...")
                try await connection.send(jsonString)
            }
        } catch {
            addLog("❌ Failed to encode VoiceStartMessage: \(error)")
            throw error
        }
    }
    
    /// Test sending VoiceAudioMessage format
    func testVoiceAudioMessage(sessionId: String, audioData: Data) async throws {
        guard let connection = webSocketConnection else {
            throw WebSocketConnectionError.disconnected
        }
        
        let testMessage = VoiceAudioMessage(sessionId: sessionId, audioData: audioData)
        let encoder = JSONEncoder()
        
        do {
            let jsonData = try encoder.encode(testMessage)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                addLog("📤 Testing VoiceAudioMessage format (audio size: \(audioData.count) bytes)...")
                try await connection.send(jsonString)
            }
        } catch {
            addLog("❌ Failed to encode VoiceAudioMessage: \(error)")
            throw error
        }
    }
    
    /// Test sending VoiceEndMessage format
    func testVoiceEndMessage(sessionId: String) async throws {
        guard let connection = webSocketConnection else {
            throw WebSocketConnectionError.disconnected
        }
        
        let testMessage = VoiceEndMessage(sessionId: sessionId)
        let encoder = JSONEncoder()
        
        do {
            let jsonData = try encoder.encode(testMessage)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                addLog("📤 Testing VoiceEndMessage format...")
                try await connection.send(jsonString)
            }
        } catch {
            addLog("❌ Failed to encode VoiceEndMessage: \(error)")
            throw error
        }
    }
    
    /// Test sending VoicePingMessage format
    func testVoicePingMessage() async throws {
        guard let connection = webSocketConnection else {
            throw WebSocketConnectionError.disconnected
        }
        
        let testMessage = VoicePingMessage()
        let encoder = JSONEncoder()
        
        do {
            let jsonData = try encoder.encode(testMessage)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                addLog("📤 Testing VoicePingMessage format...")
                try await connection.send(jsonString)
            }
        } catch {
            addLog("❌ Failed to encode VoicePingMessage: \(error)")
            throw error
        }
    }
    
    // MARK: - Test Suite Methods
    
    /// Run a complete test suite
    func runTestSuite(sessionId: String = UUID().uuidString, userId: String = "test-user") async {
        addLog("🧪 Starting test suite...")
        
        do {
            // Test 1: Connect
            try await connectToEchoServer(.echoWebSocketOrg)
            try await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
            
            // Test 2: Simple message
            try await sendTestMessage("Hello, Echo Server!")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Test 3: JSON message
            try await sendJSONTestMessage("Test JSON message")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Test 4: VoiceStartMessage format
            try await testVoiceStartMessage(sessionId: sessionId, userId: userId)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Test 5: VoicePingMessage format
            try await testVoicePingMessage()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Test 6: VoiceEndMessage format
            try await testVoiceEndMessage(sessionId: sessionId)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Test 7: VoiceAudioMessage format (with dummy audio data)
            let dummyAudioData = Data([0x00, 0x01, 0x02, 0x03, 0x04])
            try await testVoiceAudioMessage(sessionId: sessionId, audioData: dummyAudioData)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            addLog("✅ Test suite completed successfully!")
            
        } catch {
            addLog("❌ Test suite failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Logging
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        testLogs.append(logEntry)
        print("🔧 WebSocketTest: \(logEntry)")
        
        // Keep only last 50 logs
        if testLogs.count > 50 {
            testLogs.removeFirst()
        }
    }
    
    func clearLogs() {
        testLogs.removeAll()
    }
}

#endif

