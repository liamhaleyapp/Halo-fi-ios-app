//
//  ConversationSyncService.swift
//  Halo-fi-IOS
//
//  The Agent tab's conversation history lives on the server, per user
//  (Liam, 2026-09-04: a reinstall or a decode hiccup must not lose it).
//  The phone upserts each session as it grows and reads the list back;
//  UserDefaults keeps a cache for offline reads. Timestamps travel as
//  ISO-8601 strings so this does not depend on the shared decoder's
//  date strategy.
//

import Foundation

struct ConversationSyncService {
    struct EntryDTO: Codable {
        let id: String
        let speaker: String
        let text: String
        let timestamp: String
    }

    struct SessionDTO: Codable {
        let id: String
        let startedAt: String
        let updatedAt: String
        let title: String?
        let messageCount: Int
        let entries: [EntryDTO]

        enum CodingKeys: String, CodingKey {
            case id, title, entries
            case startedAt = "started_at"
            case updatedAt = "updated_at"
            case messageCount = "message_count"
        }
    }

    private struct ListDTO: Codable { let sessions: [SessionDTO] }

    private struct UpsertBody: Encodable {
        let startedAt: String
        let updatedAt: String
        let entries: [EntryDTO]

        enum CodingKeys: String, CodingKey {
            case entries
            case startedAt = "started_at"
            case updatedAt = "updated_at"
        }
    }

    func list() async throws -> [ConversationSession] {
        let out: ListDTO = try await NetworkService.shared.authenticatedRequest(
            endpoint: APIEndpoints.Agent.conversations, method: .GET, body: nil, responseType: ListDTO.self
        )
        return out.sessions.compactMap(Self.session(from:))
    }

    func upsert(_ session: ConversationSession) async throws {
        let body = UpsertBody(
            startedAt: Self.iso(session.startedAt),
            updatedAt: Self.iso(session.updatedAt),
            entries: session.entries.compactMap(Self.dto(from:))
        )
        let _: SessionDTO = try await NetworkService.shared.authenticatedRequest(
            endpoint: "\(APIEndpoints.Agent.conversations)/\(session.id.uuidString.lowercased())",
            method: .PUT, body: try JSONEncoder().encode(body), responseType: SessionDTO.self
        )
    }

    func delete(id: UUID) async throws {
        let _: EmptyResponse = try await NetworkService.shared.authenticatedRequest(
            endpoint: "\(APIEndpoints.Agent.conversations)/\(id.uuidString.lowercased())",
            method: .DELETE, body: nil, responseType: EmptyResponse.self
        )
    }

    // MARK: - Mapping

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    static func iso(_ date: Date) -> String { isoFractional.string(from: date) }

    static func date(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
            ?? isoPlain.date(from: s.replacingOccurrences(of: "+00:00", with: "Z"))
    }

    static func dto(from entry: TranscriptEntry) -> EntryDTO? {
        let speaker: String
        switch entry.speaker {
        case .user: speaker = "user"
        case .agent: speaker = "agent"
        case .system: speaker = "system"
        case .userDraft: return nil
        }
        return EntryDTO(id: entry.id.uuidString.lowercased(), speaker: speaker, text: entry.text, timestamp: iso(entry.timestamp))
    }

    static func session(from dto: SessionDTO) -> ConversationSession? {
        guard let id = UUID(uuidString: dto.id), let started = date(dto.startedAt), let updated = date(dto.updatedAt) else { return nil }
        let entries: [TranscriptEntry] = dto.entries.compactMap { e in
            let speaker: TranscriptEntry.Speaker
            switch e.speaker {
            case "user": speaker = .user
            case "agent": speaker = .agent
            case "system": speaker = .system
            default: return nil
            }
            return TranscriptEntry(id: UUID(uuidString: e.id) ?? UUID(), speaker: speaker, text: e.text,
                                   timestamp: date(e.timestamp) ?? updated, isStreaming: false)
        }
        return ConversationSession(id: id, startedAt: started, updatedAt: updated, entries: entries)
    }
}
