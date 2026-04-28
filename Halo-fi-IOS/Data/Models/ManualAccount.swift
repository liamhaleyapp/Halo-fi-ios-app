//
//  ManualAccount.swift
//  Halo-fi-IOS
//
//  User-entered account that isn't on Plaid (cash, crypto, accounts at
//  unsupported institutions). Balance is a snapshot the user updates
//  themselves — there are no transactions or syncing.
//

import Foundation

enum ManualAccountType: String, Codable, CaseIterable, Identifiable {
  case checking
  case savings
  case credit
  case investment
  case cash
  case loan
  case other

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .checking:   return "Checking"
    case .savings:    return "Savings"
    case .credit:     return "Credit Card"
    case .investment: return "Investment"
    case .cash:       return "Cash"
    case .loan:       return "Loan"
    case .other:      return "Other"
    }
  }

  var systemIcon: String {
    switch self {
    case .checking:   return "banknote"
    case .savings:    return "building.columns"
    case .credit:     return "creditcard"
    case .investment: return "chart.line.uptrend.xyaxis"
    case .cash:       return "dollarsign.circle"
    case .loan:       return "house"
    case .other:      return "circle.dotted"
    }
  }
}

struct ManualAccount: Codable, Identifiable, Hashable {
  let id: UUID
  let name: String
  let institutionName: String?
  let accountType: ManualAccountType
  let balance: Double
  let currency: String
  let notes: String?
  /// ISO-8601 string from the backend. Matches BankAccountModels — we
  /// don't decode to Date to avoid configuring a custom decoder.
  let createdAt: String?
  let updatedAt: String?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case institutionName = "institution_name"
    case accountType = "account_type"
    case balance
    case currency
    case notes
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

struct ManualAccountCreateRequest: Codable {
  let name: String
  let institutionName: String?
  let accountType: ManualAccountType
  let balance: Double
  let currency: String
  let notes: String?

  enum CodingKeys: String, CodingKey {
    case name
    case institutionName = "institution_name"
    case accountType = "account_type"
    case balance
    case currency
    case notes
  }
}

struct ManualAccountUpdateRequest: Codable {
  let name: String?
  let institutionName: String?
  let accountType: ManualAccountType?
  let balance: Double?
  let currency: String?
  let notes: String?

  enum CodingKeys: String, CodingKey {
    case name
    case institutionName = "institution_name"
    case accountType = "account_type"
    case balance
    case currency
    case notes
  }
}
