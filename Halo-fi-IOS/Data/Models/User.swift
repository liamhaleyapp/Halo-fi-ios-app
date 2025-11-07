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
    var lastName: String?
    var phone: String?
    var dateOfBirth: Date?
    let createdAt: Date
    var isOnboarded: Bool
    
    init(
        id: String = UUID().uuidString,
        email: String,
        firstName: String,
        lastName: String? = nil,
        phone: String? = nil,
        dateOfBirth: Date? = nil,
        createdAt: Date = Date(),
        isOnboarded: Bool = false
    ) {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.dateOfBirth = dateOfBirth
        self.createdAt = createdAt
        self.isOnboarded = isOnboarded
    }
    
    // Computed property for full name
    var fullName: String {
        if let lastName = lastName, !lastName.isEmpty {
            return "\(firstName) \(lastName)"
        }
        return firstName
    }
}
