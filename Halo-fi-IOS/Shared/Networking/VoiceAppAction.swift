import Foundation

struct VoiceAppAction: Codable, Sendable {
    enum Destination: String, Codable, Sendable { case money, budget, benefits, settings, accounts, transactions, calendar, income, bills, investments, attention }
    let kind: String
    let actionId: String
    let state: String
    let target: Destination
    let receipt: String
    enum CodingKeys: String, CodingKey {
        case kind, state, target, receipt
        case actionId = "action_id"
    }
}

struct VoiceAppActionPayload: Codable, Sendable {
    let type: String
    let action: VoiceAppAction
    let turnId: String?
    enum CodingKeys: String, CodingKey { case type, action; case turnId = "turn_id" }
}

@MainActor
enum VoiceNavigation {
    static let accepted = Notification.Name("haloVoiceNavigationAccepted")
    static let requested = Notification.Name("haloVoiceNavigationRequested")
    static let budgetRequested = Notification.Name("haloVoiceBudgetRequested")
    static var pendingBudget = false
    static var pendingDestination: VoiceAppAction.Destination?
    static func consumeDestination() -> VoiceAppAction.Destination? {
        defer { pendingDestination = nil; pendingBudget = false }
        return pendingDestination ?? (pendingBudget ? .budget : nil)
    }
    static func consumeBudget() -> Bool {
        defer { pendingBudget = false }
        return pendingBudget
    }
}
