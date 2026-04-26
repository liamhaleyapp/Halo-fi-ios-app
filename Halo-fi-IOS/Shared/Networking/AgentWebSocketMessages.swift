//
//  AgentWebSocketMessages.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/17/25.
//

import Foundation

// MARK: - Outgoing Messages (Client to Server)

struct ClientMessagePayload: Codable, Sendable {
    let message: String
    let context: [String: AnyCodable]?
    let sessionId: String?
    let streamAudio: Bool?

    enum CodingKeys: String, CodingKey {
        case message
        case context
        case sessionId = "session_id"
        case streamAudio = "stream_audio"
    }

    init(message: String, context: [String: AnyCodable]? = nil,
         sessionId: String? = nil, streamAudio: Bool? = nil) {
        self.message = message
        self.context = context
        self.sessionId = sessionId
        self.streamAudio = streamAudio
    }
}

// MARK: - Incoming Messages (Server to Client)

struct AgentResponsePayload: Codable, Sendable {
    let type: String
    let message: String
    let data: [String: AnyCodable]?
    let status: String?  // Server can send null
    let timestamp: String?
    let error: String?   // Server includes this field

    enum CodingKeys: String, CodingKey {
        case type
        case message
        case data
        case status
        case timestamp
        case error
    }
}

struct StreamChunkPayload: Codable, Sendable {
    let type: String
    let chunk: String
    let complete: Bool?
    let timestamp: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case chunk
        case complete
        case timestamp
    }
}

struct ErrorPayload: Codable, Sendable {
    let type: String?
    let error: String
    let code: String
    let details: [String: AnyCodable]?
    let timestamp: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case error
        case code
        case details
        case timestamp
    }
}

struct ConnectionAckPayload: Codable, Sendable {
    let type: String
    let message: String
    let connectionId: String?  // Server sends "connection_id"
    let sessionId: String?     // Some responses may use "session_id"
    let userId: String?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case type
        case message
        case connectionId = "connection_id"
        case sessionId = "session_id"
        case userId = "user_id"
        case timestamp
    }
}

struct AcknowledgmentPayload: Codable, Sendable {
    let type: String
    let text: String?
    let data: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case type, text, data
    }
}

struct AudioChunkPayload: Codable, Sendable {
    let type: String
    let audio: String
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case type, audio, timestamp
    }
}

struct AudioCompletePayload: Codable, Sendable {
    let type: String
    let message: String?
    let text: String?
    let data: [String: AnyCodable]?
    let timestamp: String?
    /// Top-level convenience field for acknowledgment audio
    /// (Phase 12+). The same flag exists in `data` for
    /// backwards compatibility, but a typed top-level field
    /// avoids the JSON-bool→Int coercion edge cases that can
    /// break `(data["is_acknowledgment"]?.value as? Bool)`.
    let isAcknowledgment: Bool?

    enum CodingKeys: String, CodingKey {
        case type, message, text, data, timestamp
        case isAcknowledgment = "is_acknowledgment"
    }

    /// The response text — server may use either "message" or "text"
    var responseText: String {
        message ?? text ?? ""
    }

    /// True when this audio_complete is the contextual ack played
    /// before the real agent response. Reads from the top-level
    /// field first, falls back to the legacy `data` dict.
    var isAck: Bool {
        if let flag = isAcknowledgment { return flag }
        return (data?["is_acknowledgment"]?.value as? Bool) == true
    }
}

// MARK: - Voice status (pre-synthesis early feedback)

/// Sent by the backend the moment the supervisor finishes (well before
/// the full agent response is ready). The text is a short pre-planned
/// utterance like "Let me check on that." iOS plays it via on-device
/// AVSpeechSynthesizer so the user hears feedback within ~500ms instead
/// of ~3s of silence while the agent graph runs.
struct VoiceStatusPayload: Codable, Sendable {
    let type: String
    let text: String
    let data: [String: AnyCodable]?
}

// MARK: - Agent Events (emitted via AsyncStream)

/// Events emitted by AgentWebSocketManager.
/// ConversationCoordinator consumes these via `for await event in manager.events`.
enum AgentEvent: Sendable {
    case connectionAck(ConnectionAckPayload)
    case streamChunk(StreamChunkPayload)
    case agentResponse(AgentResponsePayload)
    case audioChunk(AudioChunkPayload)
    case audioComplete(AudioCompletePayload)
    case acknowledgment(AcknowledgmentPayload)
    case voiceStatus(VoiceStatusPayload)
    case error(ErrorPayload)
    case permanentDisconnect
}

// MARK: - Union Types for WebSocket

enum AgentIncomingMessage: Codable, Sendable {
    case agentResponse(AgentResponsePayload)
    case streamChunk(StreamChunkPayload)
    case error(ErrorPayload)
    case connectionAck(ConnectionAckPayload)
    case acknowledgment(AcknowledgmentPayload)
    case audioChunk(AudioChunkPayload)
    case audioComplete(AudioCompletePayload)
    case voiceStatus(VoiceStatusPayload)
    case unknown(String)

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle messages without a "type" field (e.g., CONCURRENT_SESSION error)
        guard let type = try container.decodeIfPresent(String.self, forKey: .type) else {
            let payload = try ErrorPayload(from: decoder)
            self = .error(payload)
            return
        }

        switch type {
        case "agent_response":
            let payload = try AgentResponsePayload(from: decoder)
            self = .agentResponse(payload)
        case "stream":
            let payload = try StreamChunkPayload(from: decoder)
            self = .streamChunk(payload)
        case "error":
            let payload = try ErrorPayload(from: decoder)
            self = .error(payload)
        case "connection_ack":
            let payload = try ConnectionAckPayload(from: decoder)
            self = .connectionAck(payload)
        case "acknowledgment":
            let payload = try AcknowledgmentPayload(from: decoder)
            self = .acknowledgment(payload)
        case "audio_chunk":
            let payload = try AudioChunkPayload(from: decoder)
            self = .audioChunk(payload)
        case "audio_complete":
            let payload = try AudioCompletePayload(from: decoder)
            self = .audioComplete(payload)
        case "voice_status":
            let payload = try VoiceStatusPayload(from: decoder)
            self = .voiceStatus(payload)
        default:
            self = .unknown(type)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .agentResponse(let payload):
            try payload.encode(to: encoder)
        case .streamChunk(let payload):
            try payload.encode(to: encoder)
        case .error(let payload):
            try payload.encode(to: encoder)
        case .connectionAck(let payload):
            try payload.encode(to: encoder)
        case .acknowledgment(let payload):
            try payload.encode(to: encoder)
        case .audioChunk(let payload):
            try payload.encode(to: encoder)
        case .audioComplete(let payload):
            try payload.encode(to: encoder)
        case .voiceStatus(let payload):
            try payload.encode(to: encoder)
        case .unknown:
            break
        }
    }
}
