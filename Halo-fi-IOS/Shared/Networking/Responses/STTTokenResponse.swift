//
//  STTTokenResponse.swift
//  Halo-fi-IOS
//
//  Response model for /agent/stt/token endpoint.
//  Returns ElevenLabs STT credentials and configuration.
//

import Foundation

struct STTTokenResponse: Codable {
    let token: String
    let expiresAt: String?  // Backend may return null
    let modelId: String
    let websocketUrl: String
    let config: STTConfig

    struct STTConfig: Codable {
        let audioFormat: String
        let sampleRate: Int
        let commitStrategy: String
        let languageCode: String
        let includeTimestamps: Bool

        enum CodingKeys: String, CodingKey {
            case audioFormat = "audio_format"
            case sampleRate = "sample_rate"
            case commitStrategy = "commit_strategy"
            case languageCode = "language_code"
            case includeTimestamps = "include_timestamps"
        }
    }

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case modelId = "model_id"
        case websocketUrl = "websocket_url"
        case config
    }
}
