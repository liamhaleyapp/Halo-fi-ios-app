//
//  ElevenLabsMessages.swift
//  Halo-fi-IOS
//
//  WebSocket message types for ElevenLabs Scribe v2 Realtime STT.
//
//  Protocol:
//  - Audio input: JSON frames with base64-encoded PCM (input_audio_chunk)
//  - Transcription output: JSON text frames
//

import Foundation

// MARK: - Incoming Messages (Server → Client)

/// Transcription event from ElevenLabs STT
struct ElevenLabsTranscriptEvent: Codable {
    let messageType: String
    let text: String
    let isFinal: Bool?  // Optional - not present in partial_transcript
    let confidence: Double?
    let words: [TranscriptWord]?

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case text
        case isFinal = "is_final"
        case confidence
        case words
    }

    /// Check if this is a final/committed transcript
    var isCommitted: Bool {
        // final_transcript message type OR explicit is_final flag
        messageType == "final_transcript" || (isFinal ?? false)
    }
}

/// Individual word with timing info
struct TranscriptWord: Codable {
    let word: String
    let start: Double?
    let end: Double?
    let confidence: Double?
}

/// Error event from ElevenLabs
struct ElevenLabsErrorEvent: Codable {
    let messageType: String
    let error: String
    let code: String?

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case error
        case code
    }
}

/// Session started acknowledgment
struct ElevenLabsSessionStarted: Codable {
    let messageType: String
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case sessionId = "session_id"
    }
}

// MARK: - Message Type Detection

/// Wrapper for parsing incoming JSON messages
enum ElevenLabsIncomingMessage {
    case transcript(ElevenLabsTranscriptEvent)
    case error(ElevenLabsErrorEvent)
    case sessionStarted(ElevenLabsSessionStarted)
    case unknown(String)

    init(from jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else {
            self = .unknown(jsonString)
            return
        }

        // First decode just the type field (ElevenLabs uses "message_type" or "type")
        struct TypeWrapper: Codable {
            let messageType: String?
            let type: String?

            enum CodingKeys: String, CodingKey {
                case messageType = "message_type"
                case type
            }
        }

        guard let wrapper = try? JSONDecoder().decode(TypeWrapper.self, from: data),
              let messageType = wrapper.messageType ?? wrapper.type else {
            self = .unknown(jsonString)
            return
        }

        // Decode based on type
        switch messageType {
        case "transcript", "partial_transcript", "final_transcript":
            if let event = try? JSONDecoder().decode(ElevenLabsTranscriptEvent.self, from: data) {
                self = .transcript(event)
            } else {
                self = .unknown(jsonString)
            }

        case "error":
            if let event = try? JSONDecoder().decode(ElevenLabsErrorEvent.self, from: data) {
                self = .error(event)
            } else {
                self = .unknown(jsonString)
            }

        case "session_started", "connected":
            if let event = try? JSONDecoder().decode(ElevenLabsSessionStarted.self, from: data) {
                self = .sessionStarted(event)
            } else {
                self = .unknown(jsonString)
            }

        default:
            self = .unknown(jsonString)
        }
    }
}

// MARK: - Audio Frame Helper

/// Helper for preparing audio data to send to ElevenLabs
enum ElevenLabsAudioFrame {
    /// Convert PCM buffer to Data for sending as binary WebSocket frame
    static func encode(pcmData: Data) -> Data {
        // ElevenLabs expects raw PCM bytes directly as binary frame
        return pcmData
    }

    /// Convert float samples to 16-bit PCM Data
    static func floatToPCM16(_ samples: [Float]) -> Data {
        var pcmData = Data(capacity: samples.count * MemoryLayout<Int16>.size)

        for sample in samples {
            // Clamp to valid range and convert to Int16
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: int16Value) { pcmData.append(contentsOf: $0) }
        }

        return pcmData
    }
}
