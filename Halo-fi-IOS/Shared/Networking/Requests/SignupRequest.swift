//
//  SignupRequest.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/13/25.
//
import Foundation

struct SignupRequest: Codable {
  let firstName:  String
  let lastName:   String
  let email:      String
  let phone:      String
  let password:   String
  let dateOfBirth: String
  
  enum CodingKeys: String, CodingKey {
    case firstName = "first_name"
    case lastName = "last_name"
    case email
    case phone
    case password
    case dateOfBirth = "date_of_birth"
  }
}
