//
//  SignupResponse.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/4/25.
//

import Foundation

struct SignupResponse: Codable {
  let idUser: String
  
  enum CodingKeys: String, CodingKey {
    case idUser = "id_user"
  }
}
