//
//  ReceiptService.swift
//  Halo-fi-IOS
//
//  Receipt upload (multipart → POST /ssi/receipts), the server-side
//  extraction fallback, and signed view URLs. Multipart is hand-rolled the
//  same way RecordingUploader does it — NetworkService hardcodes JSON.
//

import Foundation

struct ReceiptUploadResponse: Codable, Equatable {
    let assetId: String
    let contentType: String
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case contentType = "content_type"
        case sizeBytes = "size_bytes"
    }
}

struct ReceiptExtractionResponse: Codable, Equatable {
    let amountCents: Int?
    let date: String?
    let vendor: String?
    let categoryGuess: String
    let confidence: Double
    let estimateLabel: String

    enum CodingKeys: String, CodingKey {
        case amountCents = "amount_cents"
        case date, vendor
        case categoryGuess = "category_guess"
        case confidence
        case estimateLabel = "estimate_label"
    }
}

struct ReceiptURLResponse: Codable, Equatable {
    let assetId: String
    let url: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id"
        case url
        case expiresIn = "expires_in"
    }
}

/// A receipt the user captured, ready to upload. Always JPEG or PDF —
/// HEIC from the camera roll is converted on device.
struct CapturedReceipt: Equatable {
    let data: Data
    let contentType: String
    let filename: String

    static func jpeg(_ data: Data) -> CapturedReceipt {
        CapturedReceipt(data: data, contentType: "image/jpeg", filename: "receipt.jpg")
    }

    static func pdf(_ data: Data) -> CapturedReceipt {
        CapturedReceipt(data: data, contentType: "application/pdf", filename: "receipt.pdf")
    }
}

enum ReceiptServiceError: LocalizedError {
    case notAuthenticated
    case server(Int, String)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Please sign in again."
        case .server(let code, let msg): return msg.isEmpty ? "Upload failed (\(code))." : msg
        case .tooLarge: return "Receipts must be 10 MB or smaller."
        }
    }
}

protocol ReceiptServiceProtocol {
    func upload(_ receipt: CapturedReceipt) async throws -> ReceiptUploadResponse
    func extract(assetId: String) async throws -> ReceiptExtractionResponse
    func viewURL(assetId: String) async throws -> URL
}

final class ReceiptService: ReceiptServiceProtocol {
    static let shared = ReceiptService()
    static let maxBytes = 10 * 1024 * 1024

    private let tokenStorage: TokenStorageProtocol
    private let networkService: NetworkServiceProtocol
    private let baseURL: String

    init(
        tokenStorage: TokenStorageProtocol = TokenStorage(),
        networkService: NetworkServiceProtocol = NetworkService.shared,
        baseURL: String = APIEndpoints.baseURL
    ) {
        self.tokenStorage = tokenStorage
        self.networkService = networkService
        self.baseURL = baseURL
    }

    func upload(_ receipt: CapturedReceipt) async throws -> ReceiptUploadResponse {
        guard receipt.data.count <= Self.maxBytes else { throw ReceiptServiceError.tooLarge }
        guard let token = tokenStorage.getAccessToken(), !token.isEmpty else {
            throw ReceiptServiceError.notAuthenticated
        }
        guard let url = URL(string: "\(baseURL)\(APIEndpoints.SSI.uploadReceipt)") else {
            throw URLError(.badURL)
        }
        let boundary = "halofi-receipt-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(receipt.filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(receipt.contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(receipt.data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? ""
            if status == 401 { throw ReceiptServiceError.notAuthenticated }
            throw ReceiptServiceError.server(status, detail)
        }
        return try JSONDecoder().decode(ReceiptUploadResponse.self, from: data)
    }

    func extract(assetId: String) async throws -> ReceiptExtractionResponse {
        try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.extractReceipt(assetId),
            method: .POST,
            body: nil,
            responseType: ReceiptExtractionResponse.self
        )
    }

    func viewURL(assetId: String) async throws -> URL {
        let resp: ReceiptURLResponse = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.receiptURL(assetId),
            method: .GET,
            body: nil,
            responseType: ReceiptURLResponse.self
        )
        guard let url = URL(string: resp.url) else { throw URLError(.badURL) }
        return url
    }
}
