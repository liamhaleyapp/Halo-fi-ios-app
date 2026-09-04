//
//  BudgetNotifications.swift
//  Halo-fi-IOS
//

import Foundation

extension Notification.Name {
    /// WP5 — posted when the server says budget / income / accounts data
    /// changed (`data_mutated` on the agent WebSocket). userInfo["scope"]
    /// is "budget" | "income" | "accounts". No longer fires on every reply.
    static let budgetDataDidMutate = Notification.Name("BudgetDataDidMutate")
    /// WP5 — posted for scope "accounts" so BankDataManager refreshes too.
    static let bankDataDidMutate = Notification.Name("BankDataDidMutate")
}
