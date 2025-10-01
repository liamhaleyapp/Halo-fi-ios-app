//
//  User.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import Foundation

struct User: Codable, Identifiable {
    let id: String
    let email: String
    var firstName: String
    let createdAt: Date
    var isOnboarded: Bool
    
    init(id: String = UUID().uuidString, email: String, firstName: String, createdAt: Date = Date(), isOnboarded: Bool = false) {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.createdAt = createdAt
        self.isOnboarded = isOnboarded
    }
}
