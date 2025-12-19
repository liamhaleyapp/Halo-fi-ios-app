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
    
    enum CodingKeys: String, CodingKey {
        case message
        case context
        case sessionId = "session_id"
    }
    
    init(message: String, context: [String: AnyCodable]? = nil, sessionId: String? = nil) {
        self.message = message
        self.context = context
        self.sessionId = sessionId
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
    let type: String
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

// MARK: - Union Types for WebSocket

enum AgentIncomingMessage: Codable, Sendable {
    case agentResponse(AgentResponsePayload)
    case streamChunk(StreamChunkPayload)
    case error(ErrorPayload)
    case connectionAck(ConnectionAckPayload)
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
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
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown message type: \(type)"
            )
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
        }
    }
}
