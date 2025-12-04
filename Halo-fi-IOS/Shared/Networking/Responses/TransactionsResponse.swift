//
//  TransactionsResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

// MARK: - Transactions Response
struct TransactionsResponse: Codable {
    let added: Int
    let cursor: String?
    let hasMore: Bool
    let transactions: [Transaction]
    
    enum CodingKeys: String, CodingKey {
        case added
        case cursor
        case hasMore = "has_more"
        case transactions
    }
}


