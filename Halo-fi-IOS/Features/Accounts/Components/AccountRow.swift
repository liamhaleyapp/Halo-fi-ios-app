//
//  AccountRow.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AccountRow: View {
  let account: FinancialAccount
  
  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: account.type.icon)
        .font(.caption)
        .foregroundColor(.teal)
        .frame(width: 20, height: 20)
      
      VStack(alignment: .leading, spacing: 2) {
        Text(account.nickname)
          .font(.caption)
          .foregroundColor(Color.haloTextPrimary)
        
        Text(account.type.displayName)
          .font(.caption2)
          .foregroundColor(Color.haloTextSecondary)
      }
      
      Spacer()
      
      if account.isSynced {
        Text(account.balance.formatted(.currency(code: "USD")))
          .font(.caption)
          .foregroundColor(account.balance >= 0 ? Color.haloPositive : Color.haloNegative)
      } else {
        Text("Not synced")
          .font(.caption)
          .foregroundColor(Color.haloTextSecondary)
      }
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 12)
    .background(Color.haloSecondaryBackground)
    .cornerRadius(12)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(account.nickname), \(account.type.displayName)")
    .accessibilityValue(
      account.isSynced
      ? account.balance.formatted(.currency(code: "USD"))
      : "Not synced"
    )
    .accessibilityHint("Opens account details")
  }
}

#Preview("Account Row") {
  ZStack {
    Color.haloBackground.ignoresSafeArea()
    AccountRow(account: FinancialAccount(
      id: "1",
      type: .checking,
      name: "Chase Checking",
      balance: 2547.89,
      nickname: "Main Account",
      isSynced: true
    ))
    .padding()
  }
}
