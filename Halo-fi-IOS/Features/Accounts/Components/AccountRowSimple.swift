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
          .foregroundColor(.white)
        Text(accountType.displayName)
          .font(.caption)
          .foregroundColor(.gray)
      }
      Spacer()
      Text(balance, format: .currency(code: "USD"))
        .foregroundColor(balance >= 0 ? .green : .red)
    }
  }
}
