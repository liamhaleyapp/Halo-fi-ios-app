//
//  FinancialAccount.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

struct FinancialAccount: Identifiable {
    let id: String
    let type: AccountType
    let name: String
    let balance: Double
    let nickname: String
    let isSynced: Bool
}
