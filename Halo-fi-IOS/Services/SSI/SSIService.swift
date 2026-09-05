//
//  SSIService.swift
//  Halo-fi-IOS
//
//  Networking for the SSI deduction-confirmation flow (Phase 3).
//  Backed by /ssi/exclusions and /ssi/exclusions/candidates on the
//  Python API. Thin wrapper around NetworkService so the Budget view
//  isn't coupled to URL construction.
//

import Foundation

protocol SSIServiceProtocol {
    /// Unconfirmed BWE/IRWE candidates the backend classifier spotted
    /// for the current month. Empty list when the user has no SSI flag
    /// or no transactions this month look like deduction candidates.
    func fetchCandidates(userTz: String?) async throws -> SSICandidatesResponse

    /// User's confirmed deductions for the current month plus running
    /// totals per type (drives the "you've claimed $X of BWE" line).
    func fetchExclusions(userTz: String?) async throws -> SSIExclusionsResponse

    /// Confirm a candidate as a BWE / IRWE / burial deduction. Server
    /// is idempotent on (transaction_id, exclusion_type) — calling this
    /// twice with the same args returns the same row.
    @discardableResult
    func confirm(_ request: SSICreateExclusionRequest) async throws -> SSIExclusion

    /// Undo a previously confirmed deduction by row ID.
    func deleteExclusion(_ exclusionId: String) async throws

    // MARK: - Manual deductions (Phase 8)

    /// Voice/UI-entered manual deductions for the current month.
    func fetchManualDeductions(userTz: String?) async throws -> SSIManualDeductionsResponse

    /// Log a manual deduction (cash purchase, missed-sync row, etc.).
    @discardableResult
    func createManualDeduction(_ request: SSICreateManualDeductionRequest) async throws -> SSIManualDeduction

    /// Delete a manual deduction.
    func deleteManualDeduction(_ deductionId: String) async throws

    /// WP3 — attach a receipt, change the type, flag a counselor question.
    @discardableResult
    func updateManualDeduction(_ deductionId: String, _ request: SSIUpdateManualDeductionRequest) async throws -> SSIManualDeduction

    /// WP3 — entries flagged "Not sure this counts? Ask my counselor".
    func fetchCounselorQuestions() async throws -> [SSIManualDeduction]

    /// Phase 9 — fetch the CSV export of SSI deductions for a
    /// period. ``month`` nil exports the full year. Returns raw
    /// CSV bytes the caller writes to disk for the share sheet.
    func exportDeductionsCSV(year: Int, month: Int?) async throws -> Data

    /// Phase 9b — same CSV but emailed via Mailgun. If ``to`` is nil
    /// the backend uses the user's account email; otherwise the user-
    /// provided recipient (caseworker, family member, or self when no
    /// account email is on file). Returns the address actually used +
    /// row count for in-app confirmation.
    func emailDeductionsCSV(
        year: Int,
        month: Int?,
        to: String?
    ) async throws -> SSIEmailDeductionsResponse

    // MARK: - WP6 — reminders, monthly package, submission log

    func fetchReminders(userTz: String?) async throws -> SSIRemindersResponse
    func fetchManualDeductions(userTz: String?, month: String) async throws -> SSIManualDeductionsResponse
    func fetchExclusions(userTz: String?, month: String) async throws -> SSIExclusionsResponse
    @discardableResult
    func updateExclusion(_ exclusionId: String, _ request: SSIUpdateExclusionRequest) async throws -> SSIExclusion
    func fetchPacketSummary(month: String) async throws -> SSIPacketSummary
    func downloadPacket(month: String) async throws -> Data
    func emailPacket(month: String, to: String?) async throws -> SSIEmailPacketResponse
    func fetchSubmissions() async throws -> SSISubmissionsResponse
    @discardableResult
    func markSubmitted(month: String, channel: String?, notes: String?) async throws -> SSISubmission
    @discardableResult
    func unmarkSubmitted(month: String) async throws -> SSISubmission
}

// MARK: - WP6 models

struct SSIReminder: Codable, Equatable, Identifiable {
    let id: String
    /// submit_package | receipt_overdue | attach_receipt | month_end_review
    let kind: String
    let title: String
    let body: String
    let dueOn: String?
    let deductionId: String?
    let exclusionId: String?
    let transactionId: String?
    let amountCents: Int?
    let occurredOn: String?
    let month: String?
    let vendor: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, month, vendor
        case dueOn = "due_on"
        case deductionId = "deduction_id"
        case exclusionId = "exclusion_id"
        case transactionId = "transaction_id"
        case amountCents = "amount_cents"
        case occurredOn = "occurred_on"
    }

    var isReceiptReminder: Bool { kind == "attach_receipt" || kind == "receipt_overdue" }
}

struct FieldOfficeGuidance: Codable, Equatable {
    let channel: String
    let isSet: Bool
    let title: String
    let short: String
    let steps: [String]
    let envelopeNote: String
    let keepPaper: Bool
    let notes: String?
    let neverSends: String

    enum CodingKeys: String, CodingKey {
        case channel, title, short, steps, notes
        case isSet = "is_set"
        case envelopeNote = "envelope_note"
        case keepPaper = "keep_paper"
        case neverSends = "never_sends"
    }
}

struct SSIRemindersResponse: Codable, Equatable {
    let today: String
    let reminders: [SSIReminder]
    let fieldOffice: FieldOfficeGuidance
    let counselorFinderUrl: String

    enum CodingKeys: String, CodingKey {
        case today, reminders
        case fieldOffice = "field_office"
        case counselorFinderUrl = "counselor_finder_url"
    }
}

struct SSISubmission: Codable, Equatable, Identifiable {
    let month: String
    let monthLabel: String
    let submittedAt: String?
    let channel: String?
    let packetAssetId: String?
    let packetGeneratedAt: String?
    let emailedAt: String?
    let emailedTo: String?
    let nudgedAt: String?
    let notes: String?
    let isSubmitted: Bool

    var id: String { month }

    enum CodingKeys: String, CodingKey {
        case month, channel, notes
        case monthLabel = "month_label"
        case submittedAt = "submitted_at"
        case packetAssetId = "packet_asset_id"
        case packetGeneratedAt = "packet_generated_at"
        case emailedAt = "emailed_at"
        case emailedTo = "emailed_to"
        case nudgedAt = "nudged_at"
        case isSubmitted = "is_submitted"
    }
}

struct SSISubmissionsResponse: Codable, Equatable {
    let currentMonth: String
    let previousMonth: String
    let submissions: [SSISubmission]

    enum CodingKeys: String, CodingKey {
        case submissions
        case currentMonth = "current_month"
        case previousMonth = "previous_month"
    }
}

struct SSIPacketSummary: Codable, Equatable {
    let month: String
    let monthLabel: String
    let filename: String
    let expenseKind: String
    let rowCount: Int
    let matchedCount: Int
    let receiptCount: Int
    let receiptsMissing: Int
    let totalCents: Int
    let totalsCents: [String: Int]
    let pageSummaries: [String]
    let estimateLabel: String
    let disclaimer: String
    let submission: SSISubmission?
    let fieldOffice: FieldOfficeGuidance
    let counselorFinderUrl: String
    /// 2026-09-06 — labeled paychecks reported as gross wages.
    let wageCount: Int?
    let wagesGrossCents: Int?

    enum CodingKeys: String, CodingKey {
        case month, filename, submission, disclaimer
        case monthLabel = "month_label"
        case wageCount = "wage_count"
        case wagesGrossCents = "wages_gross_cents"
        case expenseKind = "expense_kind"
        case rowCount = "row_count"
        case matchedCount = "matched_count"
        case receiptCount = "receipt_count"
        case receiptsMissing = "receipts_missing"
        case totalCents = "total_cents"
        case totalsCents = "totals_cents"
        case pageSummaries = "page_summaries"
        case estimateLabel = "estimate_label"
        case fieldOffice = "field_office"
        case counselorFinderUrl = "counselor_finder_url"
    }
}

struct SSIEmailPacketResponse: Codable, Equatable {
    let success: Bool
    let sentTo: String
    let period: String
    let filename: String
    let rowCount: Int
    let receiptCount: Int

    enum CodingKeys: String, CodingKey {
        case success, period, filename
        case sentTo = "sent_to"
        case rowCount = "row_count"
        case receiptCount = "receipt_count"
    }
}

struct SSIUpdateExclusionRequest: Encodable {
    var receiptAssetId: String? = nil
    var description: String? = nil
    var counselorQuestion: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case description
        case receiptAssetId = "receipt_asset_id"
        case counselorQuestion = "counselor_question"
    }
}

private struct SSIMarkSubmittedBody: Encodable {
    let channel: String?
    let notes: String?
}

private struct SSIEmailDeductionsBody: Encodable {
    let to: String?
}

struct SSIEmailDeductionsResponse: Codable {
    let success: Bool
    let sentTo: String
    let period: String
    let rowCount: Int

    enum CodingKeys: String, CodingKey {
        case success
        case sentTo = "sent_to"
        case period
        case rowCount = "row_count"
    }
}

// MARK: - Request / response models

struct SSICreateExclusionRequest: Encodable, Equatable {
    let transactionId: String
    let exclusionType: SSIExclusionType
    /// WP3: required — every logged expense carries a description.
    let description: String
    let notes: String?
    var receiptAssetId: String? = nil
    var receiptPending: Bool = false
    var counselorQuestion: Bool = false

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case exclusionType = "exclusion_type"
        case description
        case notes
        case receiptAssetId = "receipt_asset_id"
        case receiptPending = "receipt_pending"
        case counselorQuestion = "counselor_question"
    }
}

enum SSIExclusionType: String, Codable, CaseIterable, Equatable {
    case bwe
    case irwe
    case burial
}

struct SSIDeductionCandidate: Codable, Equatable, Identifiable {
    let transactionId: String
    let suggestedType: SSIExclusionType
    let confidence: String        // "high" | "medium" | "low"
    let amountCents: Int
    let transactionDate: String
    let description: String
    let matchedKeywords: [String]
    let reason: String

    var id: String { "\(transactionId)-\(suggestedType.rawValue)" }

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
        case suggestedType = "suggested_type"
        case confidence
        case amountCents = "amount_cents"
        case transactionDate = "transaction_date"
        case description
        case matchedKeywords = "matched_keywords"
        case reason
    }
}

struct SSICandidatesResponse: Codable, Equatable {
    let month: String
    let candidates: [SSIDeductionCandidate]
    let isBlind: Bool

    enum CodingKeys: String, CodingKey {
        case month, candidates
        case isBlind = "is_blind"
    }
}

struct SSIExclusion: Codable, Equatable, Identifiable {
    let id: String
    let transactionId: String
    let exclusionType: SSIExclusionType
    let source: String
    let confirmedAt: String
    let notes: String?
    // WP3/WP6 — optional so older payloads still decode.
    var description: String? = nil
    var receiptAssetId: String? = nil
    var needsReceipt: Bool? = nil
    var counselorQuestion: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id, description
        case transactionId = "transaction_id"
        case exclusionType = "exclusion_type"
        case source
        case confirmedAt = "confirmed_at"
        case notes
        case receiptAssetId = "receipt_asset_id"
        case needsReceipt = "needs_receipt"
        case counselorQuestion = "counselor_question"
    }
}

struct SSIExclusionsResponse: Codable, Equatable {
    let month: String
    let exclusions: [SSIExclusion]
    let totalsCents: [String: Int]

    enum CodingKeys: String, CodingKey {
        case month, exclusions
        case totalsCents = "totals_cents"
    }
}

// MARK: - Manual deductions (Phase 8)

struct SSIManualDeduction: Codable, Equatable, Identifiable {
    let id: String
    let exclusionType: SSIExclusionType
    let amountCents: Int
    let description: String
    let occurredOn: String
    let source: String          // "user_voice" | "user_manual"
    let notes: String?
    let createdAt: String
    /// Phase 8b — set when the backend reconciler matches this
    /// entry to a Plaid bank charge. Both nil = "Waiting for bank
    /// to confirm". Both non-nil = "Matched on <linkedAt>".
    let linkedTransactionId: String?
    let linkedAt: String?
    // WP3 — receipt evidence + value line. Optional so older payloads decode.
    let receiptAssetId: String?
    let receiptPending: Bool?
    let needsReceipt: Bool?
    let vendor: String?
    let counselorQuestion: Bool?
    let estimatedCheckImpactCents: Int?
    let estimateLabel: String?
    /// "matched" | "waiting_for_bank" | "needs_receipt"
    let matchStatus: String?

    var hasReceipt: Bool { !(receiptAssetId ?? "").isEmpty }
    var isMatched: Bool { linkedTransactionId != nil || matchStatus == "matched" }
    var resolvedMatchStatus: String {
        if let matchStatus { return matchStatus }
        if linkedTransactionId != nil { return "matched" }
        return hasReceipt ? "waiting_for_bank" : "needs_receipt"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case exclusionType = "exclusion_type"
        case amountCents = "amount_cents"
        case description
        case occurredOn = "occurred_on"
        case source, notes
        case createdAt = "created_at"
        case linkedTransactionId = "linked_transaction_id"
        case linkedAt = "linked_at"
        case receiptAssetId = "receipt_asset_id"
        case receiptPending = "receipt_pending"
        case needsReceipt = "needs_receipt"
        case vendor
        case counselorQuestion = "counselor_question"
        case estimatedCheckImpactCents = "estimated_check_impact_cents"
        case estimateLabel = "estimate_label"
        case matchStatus = "match_status"
    }
}

struct SSIManualDeductionsResponse: Codable, Equatable {
    let month: String
    let deductions: [SSIManualDeduction]
    let totalsCents: [String: Int]

    enum CodingKeys: String, CodingKey {
        case month, deductions
        case totalsCents = "totals_cents"
    }
}

struct SSICreateManualDeductionRequest: Encodable, Equatable {
    let exclusionType: SSIExclusionType
    let amountCents: Int
    let description: String
    /// YYYY-MM-DD; nil means "today" on the backend. Cannot be more
    /// than 90 days ago — server returns 400 otherwise.
    let occurredOn: String?
    let notes: String?
    // WP3 — receipt evidence (asset id from POST /ssi/receipts) or an
    // explicit "add it later". OCR fields are what was read; the user
    // confirmed or edited the visible amount/date/description.
    var receiptAssetId: String? = nil
    var receiptPending: Bool = false
    var vendor: String? = nil
    var extractedAmountCents: Int? = nil
    var extractedDate: String? = nil
    var extractionConfidence: Double? = nil
    var counselorQuestion: Bool = false

    enum CodingKeys: String, CodingKey {
        case exclusionType = "exclusion_type"
        case amountCents = "amount_cents"
        case description
        case occurredOn = "occurred_on"
        case notes
        case receiptAssetId = "receipt_asset_id"
        case receiptPending = "receipt_pending"
        case vendor
        case extractedAmountCents = "extracted_amount_cents"
        case extractedDate = "extracted_date"
        case extractionConfidence = "extraction_confidence"
        case counselorQuestion = "counselor_question"
    }
}

/// PATCH /ssi/manual-deductions/{id}: only set fields are sent.
struct SSIUpdateManualDeductionRequest: Encodable, Equatable {
    var receiptAssetId: String? = nil
    var exclusionType: SSIExclusionType? = nil
    var description: String? = nil
    var counselorQuestion: Bool? = nil
    var receiptPending: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case receiptAssetId = "receipt_asset_id"
        case exclusionType = "exclusion_type"
        case description
        case counselorQuestion = "counselor_question"
        case receiptPending = "receipt_pending"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(receiptAssetId, forKey: .receiptAssetId)
        try c.encodeIfPresent(exclusionType, forKey: .exclusionType)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(counselorQuestion, forKey: .counselorQuestion)
        try c.encodeIfPresent(receiptPending, forKey: .receiptPending)
    }
}

struct SSICounselorQuestionsResponse: Codable, Equatable {
    let questions: [SSIManualDeduction]
    let counselorFinderUrl: String

    enum CodingKeys: String, CodingKey {
        case questions
        case counselorFinderUrl = "counselor_finder_url"
    }
}

// MARK: - Implementation

final class SSIService: SSIServiceProtocol {
    static let shared = SSIService()

    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol = NetworkService.shared) {
        self.networkService = networkService
    }

    func fetchCandidates(userTz: String? = nil) async throws -> SSICandidatesResponse {
        let endpoint = SSIService.appendingTz(
            APIEndpoints.SSI.candidates, userTz: userTz
        )
        return try await networkService.authenticatedRequest(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            responseType: SSICandidatesResponse.self
        )
    }

    func fetchExclusions(userTz: String? = nil) async throws -> SSIExclusionsResponse {
        let endpoint = SSIService.appendingTz(
            APIEndpoints.SSI.exclusions, userTz: userTz
        )
        return try await networkService.authenticatedRequest(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            responseType: SSIExclusionsResponse.self
        )
    }

    @discardableResult
    func confirm(_ request: SSICreateExclusionRequest) async throws -> SSIExclusion {
        let body = try JSONEncoder().encode(request)
        return try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.createExclusion,
            method: .POST,
            body: body,
            responseType: SSIExclusion.self
        )
    }

    func deleteExclusion(_ exclusionId: String) async throws {
        let _: EmptyResponse = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.deleteExclusion(exclusionId),
            method: .DELETE,
            body: nil,
            responseType: EmptyResponse.self
        )
    }

    // MARK: - Manual deductions (Phase 8)

    func fetchManualDeductions(userTz: String? = nil) async throws -> SSIManualDeductionsResponse {
        let endpoint = SSIService.appendingTz(
            APIEndpoints.SSI.manualDeductions, userTz: userTz
        )
        return try await networkService.authenticatedRequest(
            endpoint: endpoint,
            method: .GET,
            body: nil,
            responseType: SSIManualDeductionsResponse.self
        )
    }

    @discardableResult
    func createManualDeduction(_ request: SSICreateManualDeductionRequest) async throws -> SSIManualDeduction {
        let body = try JSONEncoder().encode(request)
        return try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.createManualDeduction,
            method: .POST,
            body: body,
            responseType: SSIManualDeduction.self
        )
    }

    func deleteManualDeduction(_ deductionId: String) async throws {
        let _: EmptyResponse = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.deleteManualDeduction(deductionId),
            method: .DELETE,
            body: nil,
            responseType: EmptyResponse.self
        )
    }

    @discardableResult
    func updateManualDeduction(_ deductionId: String, _ request: SSIUpdateManualDeductionRequest) async throws -> SSIManualDeduction {
        let body = try JSONEncoder().encode(request)
        return try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.updateManualDeduction(deductionId),
            method: .PATCH,
            body: body,
            responseType: SSIManualDeduction.self
        )
    }

    func fetchCounselorQuestions() async throws -> [SSIManualDeduction] {
        let resp: SSICounselorQuestionsResponse = try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.counselorQuestions,
            method: .GET,
            body: nil,
            responseType: SSICounselorQuestionsResponse.self
        )
        return resp.questions
    }

    func exportDeductionsCSV(year: Int, month: Int?) async throws -> Data {
        let endpoint = APIEndpoints.SSI.exportDeductions(year: year, month: month)
        return try await networkService.authenticatedRawDataRequest(endpoint: endpoint)
    }

    func emailDeductionsCSV(
        year: Int,
        month: Int?,
        to: String?
    ) async throws -> SSIEmailDeductionsResponse {
        let endpoint = APIEndpoints.SSI.emailDeductions(year: year, month: month)
        // Only encode a body when an override recipient was supplied —
        // sending `{"to": null}` works too, but a nil body matches the
        // pre-feature shape and keeps the no-override path identical
        // to its prior behavior.
        let body: Data?
        if let to, !to.isEmpty {
            body = try? JSONEncoder().encode(SSIEmailDeductionsBody(to: to))
        } else {
            body = nil
        }
        return try await networkService.authenticatedRequest(
            endpoint: endpoint,
            method: .POST,
            body: body,
            responseType: SSIEmailDeductionsResponse.self
        )
    }

    // MARK: - WP6

    func fetchReminders(userTz: String? = nil) async throws -> SSIRemindersResponse {
        try await networkService.authenticatedRequest(
            endpoint: SSIService.appendingTz(APIEndpoints.SSI.reminders, userTz: userTz),
            method: .GET, body: nil, responseType: SSIRemindersResponse.self)
    }

    func fetchManualDeductions(userTz: String?, month: String) async throws -> SSIManualDeductionsResponse {
        try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.manualDeductions(month: month),
            method: .GET, body: nil, responseType: SSIManualDeductionsResponse.self)
    }

    func fetchExclusions(userTz: String?, month: String) async throws -> SSIExclusionsResponse {
        try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.exclusions(month: month),
            method: .GET, body: nil, responseType: SSIExclusionsResponse.self)
    }

    @discardableResult
    func updateExclusion(_ exclusionId: String, _ request: SSIUpdateExclusionRequest) async throws -> SSIExclusion {
        let body = try JSONEncoder().encode(request)
        return try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.updateExclusion(exclusionId),
            method: .PATCH, body: body, responseType: SSIExclusion.self)
    }

    func fetchPacketSummary(month: String) async throws -> SSIPacketSummary {
        try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.packetSummary(month: month),
            method: .GET, body: nil, responseType: SSIPacketSummary.self)
    }

    func downloadPacket(month: String) async throws -> Data {
        try await networkService.authenticatedRawDataRequest(endpoint: APIEndpoints.SSI.packet(month: month))
    }

    func emailPacket(month: String, to: String?) async throws -> SSIEmailPacketResponse {
        let body: Data?
        if let to, !to.isEmpty {
            body = try? JSONEncoder().encode(SSIEmailDeductionsBody(to: to))
        } else {
            body = nil
        }
        return try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.emailPacket(month: month),
            method: .POST, body: body, responseType: SSIEmailPacketResponse.self)
    }

    func fetchSubmissions() async throws -> SSISubmissionsResponse {
        try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.submissions,
            method: .GET, body: nil, responseType: SSISubmissionsResponse.self)
    }

    @discardableResult
    func markSubmitted(month: String, channel: String?, notes: String?) async throws -> SSISubmission {
        let body = try JSONEncoder().encode(SSIMarkSubmittedBody(channel: channel, notes: notes))
        return try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.markSubmitted(month: month),
            method: .POST, body: body, responseType: SSISubmission.self)
    }

    @discardableResult
    func unmarkSubmitted(month: String) async throws -> SSISubmission {
        try await networkService.authenticatedRequest(
            endpoint: APIEndpoints.SSI.unmarkSubmitted(month: month),
            method: .POST, body: nil, responseType: SSISubmission.self)
    }

    private static func appendingTz(_ endpoint: String, userTz: String?) -> String {
        guard let tz = userTz, !tz.isEmpty,
              let encoded = tz.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return endpoint
        }
        return endpoint + "?user_tz=\(encoded)"
    }
}
