//
//  MockAccountData.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Mock Account Data
struct MockAccountData {
    
    // MARK: - Checking Accounts
    static let checkingAccounts: [FinancialAccount] = [
        FinancialAccount(
            id: "mock-checking-1",
            type: .checking,
            name: "Bank of America Checking",
            balance: 4502.32,
            nickname: "BofA Checking",
            isSynced: true
        ),
        FinancialAccount(
            id: "mock-checking-2",
            type: .checking,
            name: "Chime Checking",
            balance: 1120.00,
            nickname: "Chime",
            isSynced: true
        )
    ]
    
    // MARK: - Savings Accounts
    static let savingsAccounts: [FinancialAccount] = [
        FinancialAccount(
            id: "mock-savings-1",
            type: .savings,
            name: "Ally Savings",
            balance: 9230.50,
            nickname: "Ally Savings",
            isSynced: true
        )
    ]
    
    // MARK: - Credit Cards
    static let creditCards: [FinancialAccount] = [
        FinancialAccount(
            id: "mock-credit-1",
            type: .creditCard,
            name: "Amex Platinum",
            balance: -1245.12,
            nickname: "Amex Platinum",
            isSynced: true
        ),
        FinancialAccount(
            id: "mock-credit-2",
            type: .creditCard,
            name: "Chase Sapphire",
            balance: -3010.00,
            nickname: "Chase Sapphire",
            isSynced: true
        )
    ]
    
    // MARK: - Investments
    static let investments: [FinancialAccount] = [
        FinancialAccount(
            id: "mock-investment-1",
            type: .investment,
            name: "Vanguard IRA",
            balance: 21304.23,
            nickname: "Vanguard IRA",
            isSynced: true
        ),
        FinancialAccount(
            id: "mock-investment-2",
            type: .investment,
            name: "Robinhood",
            balance: 1190.44,
            nickname: "Robinhood",
            isSynced: true
        )
    ]
    
    // MARK: - Loans
    static let loans: [FinancialAccount] = [
        FinancialAccount(
            id: "mock-loan-1",
            type: .loan,
            name: "Car Loan",
            balance: -9200.00,
            nickname: "Car Loan",
            isSynced: true
        ),
        FinancialAccount(
            id: "mock-loan-2",
            type: .loan,
            name: "Student Loan",
            balance: -15500.00,
            nickname: "Student Loan",
            isSynced: true
        )
    ]
    
    // MARK: - Helper Methods
    
    /// Get accounts for a specific type
    static func accounts(for type: AccountType) -> [FinancialAccount] {
        switch type {
        case .checking:
            return checkingAccounts
        case .savings:
            return savingsAccounts
        case .creditCard:
            return creditCards
        case .investment:
            return investments
        case .loan:
            return loans
        }
    }
    
    /// Legacy method for backward compatibility - returns tuples
    static func accountsLegacy(for type: AccountType) -> [(name: String, balance: Double)] {
        return accounts(for: type).map { ($0.name, $0.balance) }
    }
    
    /// Get display title for account type
    static func title(for type: AccountType) -> String {
        switch type {
        case .checking:
            return "Checking Accounts"
        case .savings:
            return "Savings Accounts"
        case .creditCard:
            return "Credit Cards"
        case .investment:
            return "Investments"
        case .loan:
            return "My Loans"
        }
    }
}
