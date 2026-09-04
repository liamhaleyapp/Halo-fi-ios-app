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

    enum CodingKeys: String, CodingKey {
        case success, message, data
    }

    init(success: Bool, message: String? = nil, data: UserProfileDataContainer? = nil) {
        self.success = success
        self.message = message
        self.data = data
    }

    init(from decoder: Decoder) throws {
        // Wrapped shape: {success, message, data: {...}}
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let success = try container.decodeIfPresent(Bool.self, forKey: .success) {
            self.success = success
            self.message = try container.decodeIfPresent(String.self, forKey: .message)
            self.data = try container.decodeIfPresent(UserProfileDataContainer.self, forKey: .data)
            return
        }
        // Flat DTO — GET/PUT /auth/me return the user object directly with
        // no success/data envelope. Requiring `success` made every profile
        // save "fail" client-side (silently) even though the server had
        // already committed the change.
        let user = try UserProfileData(from: decoder)
        self.success = true
        self.message = nil
        self.data = UserProfileDataContainer(user: user)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(data, forKey: .data)
    }
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
    /// Sep-2026: server-computed gating + raw benefits answers.
    let capabilities: UserCapabilities?
    let benefitsProfile: BenefitsProfile?

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
        case capabilities
        case benefitsProfile = "benefits_profile"
    }

    private enum AltKeys: String, CodingKey {
        case idUser = "id_user"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The /auth/me DTO names the id "id_user"; other payloads use "id".
        if let id = try c.decodeIfPresent(String.self, forKey: .id) {
            self.id = id
        } else {
            let alt = try decoder.container(keyedBy: AltKeys.self)
            self.id = try alt.decode(String.self, forKey: .idUser)
        }
        // Email can be absent (accounts created without one — the response
        // strips nulls). Don't let that fail the whole profile decode.
        self.email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        self.firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        self.lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        self.phone = try c.decodeIfPresent(String.self, forKey: .phone)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.score = try c.decodeIfPresent(Int.self, forKey: .score)
        self.parents = try c.decodeIfPresent(String.self, forKey: .parents)
        self.motivations = try c.decodeIfPresent(String.self, forKey: .motivations)
        self.referralCode = try c.decodeIfPresent(String.self, forKey: .referralCode)
        self.dateOfBirth = try c.decodeIfPresent(String.self, forKey: .dateOfBirth)
        self.location = try c.decodeIfPresent(String.self, forKey: .location)
        self.maritalStatus = try c.decodeIfPresent(String.self, forKey: .maritalStatus)
        self.dependent = try c.decodeIfPresent(Int.self, forKey: .dependent)
        self.householdSize = try c.decodeIfPresent(Int.self, forKey: .householdSize)
        self.emailConfirmed = try c.decodeIfPresent(Bool.self, forKey: .emailConfirmed)
        self.phoneConfirmed = try c.decodeIfPresent(Bool.self, forKey: .phoneConfirmed)
        // Tolerant: an older backend without these keys still decodes.
        self.capabilities = try? c.decodeIfPresent(UserCapabilities.self, forKey: .capabilities)
        self.benefitsProfile = try? c.decodeIfPresent(BenefitsProfile.self, forKey: .benefitsProfile)
    }
}
