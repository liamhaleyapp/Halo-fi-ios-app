//
//  WebSocketMessages.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/16/25.
//

import Foundation

// MARK: - Outgoing Messages (Client to Server)

struct VoiceStartMessage: Codable {
    let type: String = "voice_start"
    let sessionId: String
    let userId: String
    
    init(sessionId: String, userId: String) {
        self.sessionId = sessionId
        self.userId = userId
    }
}

struct VoiceAudioMessage: Codable {
    let type: String = "voice_audio"
    let sessionId: String
    let audioData: String // Base64 encoded audio data
    let timestamp: Int64
    
    init(sessionId: String, audioData: Data, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.sessionId = sessionId
        self.audioData = audioData.base64EncodedString()
        self.timestamp = timestamp
    }
}

struct VoiceEndMessage: Codable {
    let type: String = "voice_end"
    let sessionId: String
    
    init(sessionId: String) {
        self.sessionId = sessionId
    }
}

struct VoicePingMessage: Codable {
    let type: String = "ping"
    let timestamp: Int64
    
    init() {
        self.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - Incoming Messages (Server to Client)

struct VoiceResponseMessage: Codable {
    let type: String
    let sessionId: String
    let audioData: String? // Base64 encoded audio response
    let text: String? // Text response
    let timestamp: Int64
    let status: String? // "listening", "processing", "speaking"
    
    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case audioData = "audio_data"
        case text
        case timestamp
        case status
    }
}

struct VoiceErrorMessage: Codable {
    let type: String
    let error: String
    let code: Int
    let sessionId: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case error
        case code
        case sessionId = "session_id"
    }
}

struct VoicePongMessage: Codable {
    let type: String
    let timestamp: Int64
    let serverTimestamp: Int64
    
    enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case serverTimestamp = "server_timestamp"
    }
}

// MARK: - Union Types for WebSocket

enum VoiceOutgoingMessage: Encodable {
    case start(VoiceStartMessage)
    case audio(VoiceAudioMessage)
    case end(VoiceEndMessage)
    case ping(VoicePingMessage)
}

enum VoiceIncomingMessage: Codable {
    case response(VoiceResponseMessage)
    case error(VoiceErrorMessage)
    case pong(VoicePongMessage)
}
