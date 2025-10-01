//
//  FinancialInstitution.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

struct FinancialInstitution: Identifiable {
    let id: String
    let name: String
    let logo: String
    let status: ConnectionStatus
    let accounts: [FinancialAccount]
}
