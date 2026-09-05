//
//  IncomeService.swift
//  Halo-fi-IOS
//
//  Deposit labels (Liam, 2026-09-05): what a deposit was, remembered by
//  payer; the paystub gross every pay period for work income.
//

import Foundation

enum IncomeKind: String, CaseIterable, Codable {
    case workIncome = "work_income", benefit, transfer, refund, gift, other, unsure

    var title: String {
        switch self {
        case .workIncome: return "Work income"
        case .benefit: return "A benefit payment"
        case .transfer: return "A transfer between my accounts"
        case .refund: return "A refund"
        case .gift: return "A gift or help from someone"
        case .other: return "Something else"
        case .unsure: return "I'm not sure"
        }
    }

    var icon: String {
        switch self {
        case .workIncome: return "briefcase.fill"
        case .benefit: return "building.columns.fill"
        case .transfer: return "arrow.left.arrow.right"
        case .refund: return "arrow.uturn.backward"
        case .gift: return "gift.fill"
        case .other: return "ellipsis.circle"
        case .unsure: return "questionmark.circle"
        }
    }
}

struct IncomeLabelView: Codable, Equatable, Identifiable {
    let id: String
    let transactionId: String
    let kind: String
    let netCents: Int
    let grossCents: Int?
    let taxesCents: Int?
    let employer: String?
    let sourceKey: String
    let occurredOn: String
    let auto: Bool
    let needsGross: Bool
    let source: String

    enum CodingKeys: String, CodingKey {
        case id, kind, employer, auto, source
        case transactionId = "transaction_id"
        case netCents = "net_cents"
        case grossCents = "gross_cents"
        case taxesCents = "taxes_cents"
        case sourceKey = "source_key"
        case occurredOn = "occurred_on"
        case needsGross = "needs_gross"
    }
}

struct IncomeDeposit: Codable, Equatable, Identifiable {
    let transactionId: String
    let source: String
    let sourceKey: String
    let amountCents: Int
    let occurredOn: String
    let accountId: String?
    let label: IncomeLabelView?

    var id: String { transactionId }

    enum CodingKeys: String, CodingKey {
        case source, label
        case transactionId = "transaction_id"
        case sourceKey = "source_key"
        case amountCents = "amount_cents"
        case occurredOn = "occurred_on"
        case accountId = "account_id"
    }
}

struct IncomeSource: Codable, Equatable, Identifiable {
    let sourceKey: String
    let kind: String
    let employer: String?
    let lastGrossCents: Int?
    let lastNetCents: Int?
    let lastPaidOn: String?
    let cadenceDays: Int?

    var id: String { sourceKey }

    enum CodingKeys: String, CodingKey {
        case kind, employer
        case sourceKey = "source_key"
        case lastGrossCents = "last_gross_cents"
        case lastNetCents = "last_net_cents"
        case lastPaidOn = "last_paid_on"
        case cadenceDays = "cadence_days"
    }
}

struct IncomeSummary: Codable, Equatable {
    struct Employer: Codable, Equatable, Identifiable {
        let employer: String
        let grossCents: Int
        let netCents: Int
        let paychecks: Int
        var id: String { employer }
        enum CodingKeys: String, CodingKey {
            case employer, paychecks
            case grossCents = "gross_cents"
            case netCents = "net_cents"
        }
    }

    let month: String
    let sources: [IncomeSource]
    let workIncome: [Employer]
    let workIncomeGrossCents: Int
    let workIncomeNetCents: Int
    let benefitCents: Int
    let paychecksNeedingGross: Int
    let labels: [IncomeLabelView]

    enum CodingKeys: String, CodingKey {
        case month, sources, labels
        case workIncome = "work_income"
        case workIncomeGrossCents = "work_income_gross_cents"
        case workIncomeNetCents = "work_income_net_cents"
        case benefitCents = "benefit_cents"
        case paychecksNeedingGross = "paychecks_needing_gross"
    }
}

protocol IncomeServiceProtocol {
    func deposits(days: Int, unlabeledOnly: Bool) async throws -> [IncomeDeposit]
    func label(transactionId: String, kind: IncomeKind, grossCents: Int?, employer: String?) async throws -> IncomeLabelView
    func updateLabel(id: String, grossCents: Int?) async throws -> IncomeLabelView
    func deleteLabel(id: String) async throws
    func summary(month: String?) async throws -> IncomeSummary
}

final class IncomeService: IncomeServiceProtocol {
    static let shared = IncomeService()

    private struct DepositsOut: Codable { let today: String; let deposits: [IncomeDeposit] }
    private struct LabelOut: Codable { let label: IncomeLabelView }
    private struct LabelBody: Encodable {
        let transaction_id: String
        let kind: String
        let gross_cents: Int?
        let employer: String?
        let remember: Bool
    }
    private struct PatchBody: Encodable { let gross_cents: Int? }

    func deposits(days: Int = 30, unlabeledOnly: Bool = false) async throws -> [IncomeDeposit] {
        let out: DepositsOut = try await NetworkService.shared.authenticatedRequest(
            endpoint: "\(APIEndpoints.Income.deposits)?days=\(days)&status=\(unlabeledOnly ? "unlabeled" : "all")",
            method: .GET, body: nil, responseType: DepositsOut.self
        )
        return out.deposits
    }

    func label(transactionId: String, kind: IncomeKind, grossCents: Int?, employer: String?) async throws -> IncomeLabelView {
        let body = LabelBody(transaction_id: transactionId, kind: kind.rawValue, gross_cents: grossCents, employer: employer, remember: true)
        let out: LabelOut = try await NetworkService.shared.authenticatedRequest(
            endpoint: APIEndpoints.Income.labels, method: .POST, body: try JSONEncoder().encode(body), responseType: LabelOut.self
        )
        return out.label
    }

    func updateLabel(id: String, grossCents: Int?) async throws -> IncomeLabelView {
        let out: LabelOut = try await NetworkService.shared.authenticatedRequest(
            endpoint: APIEndpoints.Income.label(id), method: .PATCH,
            body: try JSONEncoder().encode(PatchBody(gross_cents: grossCents)), responseType: LabelOut.self
        )
        return out.label
    }

    func deleteLabel(id: String) async throws {
        let _: EmptyResponse = try await NetworkService.shared.authenticatedRequest(
            endpoint: APIEndpoints.Income.label(id), method: .DELETE, body: nil, responseType: EmptyResponse.self
        )
    }

    func summary(month: String?) async throws -> IncomeSummary {
        var endpoint = APIEndpoints.Income.summary
        if let month { endpoint += "?month=\(month)" }
        return try await NetworkService.shared.authenticatedRequest(
            endpoint: endpoint, method: .GET, body: nil, responseType: IncomeSummary.self
        )
    }
}
