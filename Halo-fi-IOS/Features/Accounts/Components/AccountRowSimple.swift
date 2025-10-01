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
  
  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(name)
          .foregroundColor(.white)
        Text("Checking")
          .font(.caption)
          .foregroundColor(.gray)
      }
      Spacer()
      Text(balance, format: .currency(code: "USD"))
        .foregroundColor(balance >= 0 ? .green : .red)
    }
    .listRowBackground(Color.gray.opacity(0.15))
  }
}
