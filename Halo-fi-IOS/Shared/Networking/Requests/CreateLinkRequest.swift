//
//  CreateLinkRequest.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/13/25.
//

import Foundation

struct PlaidLinkRequest: Codable {
  let products: [String]
  let countryCodes: [String]
  let language: String
  
  init(products: [String], countryCodes: [String], language: String) {
    self.products = products
    self.countryCodes = countryCodes
    self.language = language
  }
  
  init() {
    self.products = [
      "transactions",
      "auth"
    ]
    self.countryCodes = [
      "US",
      "MX"
    ]
    self.language = "es"
  }
}
