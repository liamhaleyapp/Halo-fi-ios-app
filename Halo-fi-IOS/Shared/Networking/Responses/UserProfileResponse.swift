//
//  UserProfileResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/5/25.
//

import Foundation

struct UserProfileResponse: Codable {
    let success: Bool
    let message: String?
    let data: UserProfileDataContainer?
}

struct UserProfileDataContainer: Codable {
    let success: Bool?
    let message: String?
    let user: UserProfileData
    
    private enum CodingKeys: String, CodingKey {
        case success
        case message
        case user
    }
    
    init(user: UserProfileData, success: Bool? = nil, message: String? = nil) {
        self.user = user
        self.success = success
        self.message = message
    }
    
    init(from decoder: Decoder) throws {
        if let directUser = try? UserProfileData(from: decoder) {
            self.user = directUser
            self.success = nil
            self.message = nil
            return
        }
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try container.decodeIfPresent(Bool.self, forKey: .success)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        self.user = try container.decode(UserProfileData.self, forKey: .user)
    }
    
    func encode(to encoder: Encoder) throws {
        if success == nil && message == nil {
            try user.encode(to: encoder)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(success, forKey: .success)
            try container.encodeIfPresent(message, forKey: .message)
            try container.encode(user, forKey: .user)
        }
    }
}

struct UserProfileData: Codable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String?
    let phone: String?
    let status: String?
    let score: Int?
    let parents: String?
    let motivations: String?
    let referralCode: String?
    let dateOfBirth: String?
    let location: String?
    let maritalStatus: String?
    let dependent: Int?
    let householdSize: Int?
    let emailConfirmed: Bool?
    let phoneConfirmed: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case phone
        case status
        case score
        case parents
        case motivations
        case referralCode = "referal_code"
        case dateOfBirth = "date_of_birth"
        case location
        case maritalStatus = "marital_status"
        case dependent
        case householdSize = "household_size"
        case emailConfirmed = "email_confirmed"
        case phoneConfirmed = "phone_confirmed"
    }
}
