//
//  BankMultiConnectRequest.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/10/25.
//

import Foundation

struct BankMultiConnectRequest: Codable {
    let publicTokens: [String]
    
    enum CodingKeys: String, CodingKey {
        case publicTokens = "public_tokens"
    }
}
