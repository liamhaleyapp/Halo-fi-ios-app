//
//  BudgetNotifications.swift
//  Halo-fi-IOS
//
//  Cross-module signals related to budget-overview cache state.
//  Pulled out so the agent-side coordinator (which posts the
//  notification) doesn't have to know about BudgetDataManager
//  beyond the name.
//

import Foundation

extension Notification.Name {
    /// Posted when out-of-band activity may have mutated the user's
    /// budget state on the server — most commonly an agent reply
    /// landing after a voice command ("set my food budget to $200",
    /// "save fifty dollars on Uber as a BWE"). BudgetDataManager
    /// observes this and marks its cache stale so the next tab
    /// visit fetches fresh overview data instead of serving the
    /// pre-mutation rows. Coarse on purpose: posting on every
    /// agent reply over-refreshes for non-mutating turns ("what's
    /// my balance") but never misses a real mutation. When the
    /// backend ships a `data.mutated` signal in the agent payload
    /// we can scope the post to mutating turns only.
    static let budgetDataDidMutate = Notification.Name("BudgetDataDidMutate")
}
