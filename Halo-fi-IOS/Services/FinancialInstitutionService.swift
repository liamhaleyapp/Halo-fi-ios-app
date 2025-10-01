//
//  FinancialInstitutionService.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Financial Institution Service
struct FinancialInstitutionService {
    
    // MARK: - Public Methods
    
    /// Get all connected institutions from a collection
    static func connectedInstitutions(from institutions: [FinancialInstitution]) -> [FinancialInstitution] {
        return institutions.filter { $0.status == .connected }
    }
    
    /// Get all disconnected institutions from a collection
    static func disconnectedInstitutions(from institutions: [FinancialInstitution]) -> [FinancialInstitution] {
        return institutions.filter { $0.status == .disconnected }
    }
    
    /// Get all pending institutions from a collection
    static func pendingInstitutions(from institutions: [FinancialInstitution]) -> [FinancialInstitution] {
        return institutions.filter { $0.status == .pending }
    }
    
    /// Get total balance across all connected and synced accounts
    static func totalBalance(from institutions: [FinancialInstitution]) -> Double {
        return institutions
            .filter { $0.status == .connected }
            .flatMap { $0.accounts }
            .filter { $0.isSynced }
            .reduce(0) { $0 + $1.balance }
    }
    
    /// Get total balance for a specific institution
    static func totalBalance(for institution: FinancialInstitution) -> Double {
        return institution.accounts
            .filter { $0.isSynced }
            .reduce(0) { $0 + $1.balance }
    }
    
    /// Get all accounts of a specific type from institutions
    static func accounts(ofType type: AccountType, from institutions: [FinancialInstitution]) -> [FinancialAccount] {
        return institutions
            .flatMap { $0.accounts }
            .filter { $0.type == type }
    }
    
    /// Find institution by ID from a collection
    static func institution(with id: String, from institutions: [FinancialInstitution]) -> FinancialInstitution? {
        return institutions.first { $0.id == id }
    }
    
    /// Get count of connected institutions
    static func connectedCount(from institutions: [FinancialInstitution]) -> Int {
        return connectedInstitutions(from: institutions).count
    }
}
