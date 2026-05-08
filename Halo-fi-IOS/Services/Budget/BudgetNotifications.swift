//
//  BudgetNotifications.swift
//  Halo-fi-IOS
//

import Foundation

extension Notification.Name {
    /// Posted when out-of-band activity may have mutated server-side
    /// budget state — typically an agent reply. Coarse on purpose:
    /// fires on every reply, not just mutating ones.
    static let budgetDataDidMutate = Notification.Name("BudgetDataDidMutate")
}
