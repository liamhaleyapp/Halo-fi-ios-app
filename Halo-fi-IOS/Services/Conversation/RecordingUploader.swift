//
//  RecordingUploader.swift
//  Halo-fi-IOS
//
//  Encodes accumulated mic buffers as 16kHz mono 16-bit WAV and
//  uploads them to the backend's /agent/recordings/upload endpoint
//  for training-data collection. Designed to run fire-and-forget
//  AFTER the user's transcript has already been sent to the agent —
//  the upload never blocks the conversation path.
//
//  Format choice: raw PCM WAV (lossless) at 16kHz mono. STT and
//  voice-model training pipelines all consume this without
//  conversion. ~32KB/sec, ~320KB per 10-sec utterance.
//

import Foundation
import AVFoundation

/// Backend, STT, and Plaid all standardize on 16kHz mono for voice —
/// match it here so the uploaded file is immediately usable as
/// training input. Constant lives at file scope so the encode helpers
/// (which are nonisolated free functions for thread-safety) can read
/// it without touching the singleton's actor isolation.
private let kRecordingTargetSampleRate: Double = 16000

/// Where we POST. Backend reads multipart fields:
///   - audio (file)
///   - session_id, turn_number, user_transcript, audio_format,
///     audio_duration_ms (form fields)
private let kRecordingUploadEndpoint = "/agent/recordings/upload"

/// Match NetworkService's default for parity with every other call.
private let kBackendBaseURL = "https://halofiapp-production.up.railway.app"

final class RecordingUploader: @unchecked Sendable {
    private let tokenStorage: TokenStorageProtocol
    private let session: URLSession

    /// Per-turn tracking so `setAgentResponse(turnNumber:)` can find
    /// the recording id once the upload has finished. Each entry is a
    /// task that resolves to the recording id (or nil if the upload
    /// failed). Access is serialized through `pendingLock`.
    private let pendingLock = NSLock()
    private var pendingUploads: [Int: Task<String?, Never>] = [:]

    init(
        tokenStorage: TokenStorageProtocol = TokenStorage(),
        session: URLSession = .shared
    ) {
        self.tokenStorage = tokenStorage
        self.session = session
    }

    /// Snapshot the buffers, encode WAV in the background, and POST.
    /// Failures are logged but never thrown — the conversation path
    /// must not depend on this succeeding. The recording id (if any)
    /// is held internally for a later `setAgentResponse` call.
    func upload(
        buffers: [AVAudioPCMBuffer],
        sessionId: String,
        turnNumber: Int,
        userTranscript: String?
    ) {
        guard !buffers.isEmpty else { return }

        // Off-main detached so WAV encoding (Float→Int16 over tens of
        // thousands of frames) doesn't compete with the audio buffers
        // still arriving on the main actor.
        let task = Task.detached(priority: .utility) { [weak self] () -> String? in
            guard let self else { return nil }
            guard let wavData = encodeBuffersToWAV(buffers) else {
                Logger.warning("RecordingUploader: WAV encoding produced no data — skipping upload")
                return nil
            }

            let durationMs = Int(
                (Double(wavData.count - 44) /  // subtract WAV header
                 (kRecordingTargetSampleRate * 2.0)) * 1000.0
            )

            do {
                let recordingId = try await self.postMultipart(
                    audioData: wavData,
                    sessionId: sessionId,
                    turnNumber: turnNumber,
                    userTranscript: userTranscript ?? "",
                    audioDurationMs: durationMs
                )
                Logger.info("RecordingUploader: turn \(turnNumber) uploaded (\(wavData.count) bytes, ~\(durationMs)ms, id=\(recordingId ?? "nil"))")
                return recordingId
            } catch {
                Logger.warning("RecordingUploader: upload failed — \(error)")
                return nil
            }
        }

        pendingLock.lock()
        pendingUploads[turnNumber] = task
        pendingLock.unlock()
    }

    /// Backfill the agent-side fields once the reply has landed. Waits
    /// for the matching upload to complete so we know the recording
    /// id, then PATCHes it. Fire-and-forget — failures are logged but
    /// never surface to the conversation path.
    func setAgentResponse(
        turnNumber: Int,
        agentResponse: String,
        responseTimeMs: Int?,
        agentName: String? = nil
    ) {
        pendingLock.lock()
        let uploadTask = pendingUploads.removeValue(forKey: turnNumber)
        pendingLock.unlock()

        guard let uploadTask else {
            Logger.warning("RecordingUploader: no pending upload for turn \(turnNumber) — skipping agent_response patch")
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let recordingId = await uploadTask.value, !recordingId.isEmpty else {
                Logger.warning("RecordingUploader: upload for turn \(turnNumber) had no id — skipping agent_response patch")
                return
            }
            do {
                try await self.patchAgentResponse(
                    recordingId: recordingId,
                    agentResponse: agentResponse,
                    responseTimeMs: responseTimeMs,
                    agentName: agentName
                )
                Logger.info("RecordingUploader: turn \(turnNumber) agent_response patched (id=\(recordingId))")
            } catch {
                Logger.warning("RecordingUploader: patch failed for turn \(turnNumber) — \(error)")
            }
        }
    }

    // MARK: - Retry helpers

    /// Race the request against transient backend / network failures.
    /// Retries on URLError (timeout, DNS, connection drop) and on
    /// retriable HTTP responses (408 Request Timeout, 429 Too Many
    /// Requests, all 5xx). 4xx responses outside that whitelist are
    /// client-side problems that won't self-heal — fail fast.
    /// Exponential backoff (2s → 4s) with ±50% jitter so multiple
    /// clients don't all retry on the same tick after a backend
    /// hiccup. Status validation lives here so the retry loop can
    /// react to 5xx; callers receive only 2xx responses.
    private func dataWithRetry(
        for request: URLRequest,
        attempts: Int = 3,
        initialDelay: Duration = .seconds(2)
    ) async throws -> (Data, URLResponse) {
        var delay = initialDelay
        var lastError: Error = URLError(.cannotConnectToHost)

        for attempt in 1...attempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if (200..<300).contains(http.statusCode) {
                    return (data, response)
                }
                // Non-2xx: surface as a URLError so the catch decides whether to retry.
                throw URLError(.init(rawValue: http.statusCode))
            } catch {
                lastError = error
                guard attempt < attempts, Self.isRetriable(error) else {
                    throw error
                }
                let baseSeconds = Double(delay.components.seconds)
                let jitteredMs = Int(baseSeconds * 1000 * Double.random(in: 0.5...1.5))
                try? await Task.sleep(for: .milliseconds(jitteredMs))
                delay *= 2
            }
        }
        throw lastError
    }

    private static func isRetriable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        let code = urlError.errorCode
        // We synthesize URLError(.init(rawValue: statusCode)) for non-2xx
        // responses, so a positive code in HTTP range is an HTTP status.
        if (100..<600).contains(code) {
            switch code {
            case 408, 429, 500..<600: return true
            default: return false
            }
        }
        // Real URLError (negative code: timeout, DNS, lost connection,
        // etc.) — all transient, all worth a retry.
        return true
    }

    // MARK: - Multipart upload

    private func postMultipart(
        audioData: Data,
        sessionId: String,
        turnNumber: Int,
        userTranscript: String,
        audioDurationMs: Int
    ) async throws -> String? {
        guard let token = tokenStorage.getAccessToken(), !token.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        guard let url = URL(string: "\(kBackendBaseURL)\(kRecordingUploadEndpoint)") else {
            throw URLError(.badURL)
        }

        let boundary = "halofi-rec-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendField("session_id", sessionId)
        appendField("turn_number", String(turnNumber))
        appendField("user_transcript", userTranscript)
        appendField("audio_format", "wav")
        appendField("audio_duration_ms", String(audioDurationMs))

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"audio\"; filename=\"turn_\(turnNumber).wav\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await dataWithRetry(for: request)

        // Backend returns { success, id, audio_url }. Extract id so the
        // later PATCH can target this row.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = json["id"] as? String {
            return id
        }
        return nil
    }

    // MARK: - Agent-response PATCH

    private func patchAgentResponse(
        recordingId: String,
        agentResponse: String,
        responseTimeMs: Int?,
        agentName: String?
    ) async throws {
        guard let token = tokenStorage.getAccessToken(), !token.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        guard let url = URL(string: "\(kBackendBaseURL)/agent/recordings/\(recordingId)") else {
            throw URLError(.badURL)
        }

        var payload: [String: Any] = ["agent_response": agentResponse]
        if let responseTimeMs { payload["response_time_ms"] = responseTimeMs }
        if let agentName { payload["agent_name"] = agentName }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        _ = try await dataWithRetry(for: request)
    }
}

// MARK: - WAV encoding (free functions for nonisolated use)

/// Convert AVAudioPCMBuffer chain (Float32, native sample rate)
/// into a single 16kHz mono 16-bit-PCM WAV file body.
private func encodeBuffersToWAV(_ buffers: [AVAudioPCMBuffer]) -> Data? {
    var int16Samples: [Int16] = []
    int16Samples.reserveCapacity(64_000) // ~2 sec at 16kHz, grows as needed

    for buffer in buffers {
        guard let channelData = buffer.floatChannelData?[0] else { continue }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { continue }

        let inputSampleRate = buffer.format.sampleRate
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        let resampled: [Float]
        if inputSampleRate != kRecordingTargetSampleRate {
            resampled = linearResample(samples, from: inputSampleRate, to: kRecordingTargetSampleRate)
        } else {
            resampled = samples
        }

        for s in resampled {
            let clamped = max(-1.0, min(1.0, s))
            int16Samples.append(Int16(clamped * Float(Int16.max)))
        }
    }

    guard !int16Samples.isEmpty else { return nil }

    let pcmBytes = int16Samples.withUnsafeBufferPointer { buf in
        Data(buffer: buf)
    }

    return wrapInWAVHeader(
        pcmData: pcmBytes,
        sampleRate: UInt32(kRecordingTargetSampleRate),
        channels: 1,
        bitsPerSample: 16
    )
}

/// Linear interpolation resampler — same approach as
/// ElevenLabsSTTService. Quality is sufficient for training data;
/// AVAudioConverter would be heavier and adds async complexity for
/// negligible win on voice content.
private func linearResample(
    _ samples: [Float],
    from inputRate: Double,
    to outputRate: Double
) -> [Float] {
    guard inputRate != outputRate, !samples.isEmpty else { return samples }
    let ratio = inputRate / outputRate
    let outputLength = Int(Double(samples.count) / ratio)
    var output = [Float](repeating: 0, count: outputLength)
    for i in 0..<outputLength {
        let srcIndex = Double(i) * ratio
        let srcIndexInt = Int(srcIndex)
        let fraction = Float(srcIndex - Double(srcIndexInt))
        if srcIndexInt + 1 < samples.count {
            output[i] = samples[srcIndexInt] * (1 - fraction)
                      + samples[srcIndexInt + 1] * fraction
        } else if srcIndexInt < samples.count {
            output[i] = samples[srcIndexInt]
        }
    }
    return output
}

/// Build a minimal RIFF/WAV header in front of the PCM body. Only
/// the standard subset every audio tool understands (no fact / list
/// chunks, no extended fmt). 44 bytes total.
private func wrapInWAVHeader(
    pcmData: Data,
    sampleRate: UInt32,
    channels: UInt16,
    bitsPerSample: UInt16
) -> Data {
    let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign = channels * (bitsPerSample / 8)
    let dataSize = UInt32(pcmData.count)
    let chunkSize = 36 + dataSize

    var header = Data()
    header.append(contentsOf: Array("RIFF".utf8))
    header.append(contentsOf: le32(chunkSize))
    header.append(contentsOf: Array("WAVE".utf8))
    header.append(contentsOf: Array("fmt ".utf8))
    header.append(contentsOf: le32(16))            // fmt chunk size
    header.append(contentsOf: le16(1))             // audio format = 1 (PCM)
    header.append(contentsOf: le16(channels))
    header.append(contentsOf: le32(sampleRate))
    header.append(contentsOf: le32(byteRate))
    header.append(contentsOf: le16(blockAlign))
    header.append(contentsOf: le16(bitsPerSample))
    header.append(contentsOf: Array("data".utf8))
    header.append(contentsOf: le32(dataSize))

    var out = Data(capacity: header.count + pcmData.count)
    out.append(header)
    out.append(pcmData)
    return out
}

private func le16(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
}

private func le32(_ value: UInt32) -> [UInt8] {
    [
        UInt8(value & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 24) & 0xff),
    ]
}
