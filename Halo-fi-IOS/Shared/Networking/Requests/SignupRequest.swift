//
//  SignupRequest.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/13/25.
//
import Foundation

struct SignupRequest: Codable {
  let firstName: String
  let lastName: String
  let email: String
  // Phone and date of birth are optional (Apple 5.1.1(v) bars requiring
  // phone; DOB isn't core to functionality and was removed from the form).
  let phone: String?
  let password: String
  let dateOfBirth: String?
  
  enum CodingKeys: String, CodingKey {
    case firstName = "first_name"
    case lastName = "last_name"
    case email
    case phone
    case password
    case dateOfBirth = "date_of_birth"
  }
}
