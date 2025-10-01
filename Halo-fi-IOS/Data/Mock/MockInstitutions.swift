//
//  MockInstitutions.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Mock Financial Data
struct MockInstitutions {
    
    /// Sample financial institutions with their associated accounts
    static let institutions: [FinancialInstitution] = [
        FinancialInstitution(
            id: "1",
            name: "Chase Bank",
            logo: "building.2.fill",
            status: .connected,
            accounts: [
                FinancialAccount(id: "1", type: .checking, name: "Chase Checking", balance: 2547.89, nickname: "Main Account", isSynced: true),
                FinancialAccount(id: "2", type: .savings, name: "Chase Savings", balance: 12500.00, nickname: "Emergency Fund", isSynced: true)
            ]
        ),
        FinancialInstitution(
            id: "2",
            name: "Bank of America",
            logo: "building.columns.fill",
            status: .connected,
            accounts: [
                FinancialAccount(id: "3", type: .checking, name: "BofA Checking", balance: 892.45, nickname: "Daily Use", isSynced: true),
                FinancialAccount(id: "4", type: .creditCard, name: "BofA Credit Card", balance: -1250.67, nickname: "Travel Card", isSynced: true)
            ]
        ),
        FinancialInstitution(
            id: "3",
            name: "Wells Fargo",
            logo: "building.2",
            status: .disconnected,
            accounts: [
                FinancialAccount(id: "5", type: .savings, name: "Wells Fargo Savings", balance: 0.0, nickname: "Old Savings", isSynced: false)
            ]
        )
    ]
    
    // MARK: - Mock-specific convenience methods
    // These delegate to the service but provide mock data by default
    
    /// Get a specific institution by ID from mock data
    static func institution(with id: String) -> FinancialInstitution? {
        return FinancialInstitutionService.institution(with: id, from: institutions)
    }
    
    /// Get all connected institutions from mock data
    static var connectedInstitutions: [FinancialInstitution] {
        return FinancialInstitutionService.connectedInstitutions(from: institutions)
    }
    
    /// Get all disconnected institutions from mock data
    static var disconnectedInstitutions: [FinancialInstitution] {
        return FinancialInstitutionService.disconnectedInstitutions(from: institutions)
    }
    
    /// Get all pending institutions from mock data
    static var pendingInstitutions: [FinancialInstitution] {
        return FinancialInstitutionService.pendingInstitutions(from: institutions)
    }
    
    /// Get total balance across all connected accounts from mock data
    static var totalBalance: Double {
        return FinancialInstitutionService.totalBalance(from: institutions)
    }
}
