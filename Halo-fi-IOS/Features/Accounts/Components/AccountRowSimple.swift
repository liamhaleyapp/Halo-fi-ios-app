//
//  AccountRowSimple.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AccountRowSimple: View {
  let name: String
  let balance: Double
  let accountType: AccountType
  
  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(name)
          .foregroundColor(Color.haloTextPrimary)
        Text(accountType.displayName)
          .font(.caption)
          .foregroundColor(Color.haloTextSecondary)
      }
      Spacer()
      Text(balance, format: .currency(code: "USD"))
        .foregroundColor(balance >= 0 ? Color.haloPositive : Color.haloNegative)
    }
  }
}
