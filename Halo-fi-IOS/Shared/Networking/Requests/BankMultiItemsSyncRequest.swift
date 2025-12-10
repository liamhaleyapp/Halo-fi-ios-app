//
//  BankMultiItemsSyncRequest.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/18/25.
//

import Foundation

struct BankMultiItemsSyncRequest: Codable {
    let itemIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case itemIds = "item_ids"
    }
}
