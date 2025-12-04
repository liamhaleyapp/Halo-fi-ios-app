//
//  BankSyncResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Bank Sync Response
struct BankSyncResponse: Codable {
    let success: Bool
    let message: String?
    let accountsUpdated: Int?
    let transactionsUpdated: Int?
    let requestId: String?
}


