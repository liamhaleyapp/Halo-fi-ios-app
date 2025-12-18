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
  let layerOption: Bool

  enum CodingKeys: String, CodingKey {
    case products
    case countryCodes = "country_codes"
    case language
    case layerOption = "layer_option"
  }

  init(products: [String], countryCodes: [String], language: String, layerOption: Bool = false) {
    self.products = products
    self.countryCodes = countryCodes
    self.language = language
    self.layerOption = layerOption
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
    self.layerOption = false
  }
}
