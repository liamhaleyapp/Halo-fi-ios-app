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
    let plaidItemId: String?

    /// Creates a FinancialAccount from a BankAccount (Plaid data)
    init(from bankAccount: BankAccount, plaidItemId: String? = nil) {
        self.id = bankAccount.idAccount
        self.type = AccountType.from(bankAccount.type)
        self.name = bankAccount.name
        self.balance = bankAccount.currentBalance ?? 0
        self.nickname = bankAccount.name
        self.isSynced = bankAccount.isActive
        self.plaidItemId = plaidItemId ?? bankAccount.plaidItemId
    }

    /// Standard memberwise initializer
    init(id: String, type: AccountType, name: String, balance: Double, nickname: String, isSynced: Bool, plaidItemId: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.balance = balance
        self.nickname = nickname
        self.isSynced = isSynced
        self.plaidItemId = plaidItemId
    }
}
