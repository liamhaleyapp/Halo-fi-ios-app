//
//  UpdateUserProfileRequest.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/5/25.
//

import Foundation

struct UpdateUserProfileRequest: Codable {
    let firstName: String?
    let lastName: String?
    let status: String?
    let parents: String?
    let motivations: String?
    let referralCode: String?
    let dateOfBirth: String?
    let location: String?
    let maritalStatus: String?
    let dependent: Int?
    let householdSize: Int?
    let phone: String?
    
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case status
        case parents
        case motivations
        case referralCode = "referal_code"
        case dateOfBirth = "date_of_birth"
        case location
        case maritalStatus = "marital_status"
        case dependent
        case householdSize = "household_size"
        case phone
    }
}
