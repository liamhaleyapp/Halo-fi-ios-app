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
    static let checkingAccounts: [(name: String, balance: Double)] = [
        ("Bank of America Checking", 4502.32),
        ("Chime Checking", 1120.00)
    ]
    
    // MARK: - Savings Accounts
    static let savingsAccounts: [(name: String, balance: Double)] = [
        ("Ally Savings", 9230.50)
    ]
    
    // MARK: - Credit Cards
    static let creditCards: [(name: String, balance: Double)] = [
        ("Amex Platinum", -1245.12),
        ("Chase Sapphire", -3010.00)
    ]
    
    // MARK: - Investments
    static let investments: [(name: String, balance: Double)] = [
        ("Vanguard IRA", 21304.23),
        ("Robinhood", 1190.44)
    ]
    
    // MARK: - Loans
    static let loans: [(name: String, balance: Double)] = [
        ("Car Loan", -9200.00),
        ("Student Loan", -15500.00)
    ]
    
    // MARK: - Helper Methods
    
    /// Get accounts for a specific type
    static func accounts(for type: AccountType) -> [(name: String, balance: Double)] {
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
