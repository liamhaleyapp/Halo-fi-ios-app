//
//  AccountDetailRow.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AccountDetailRow: View {
  let account: FinancialAccount
  
  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: account.type.icon)
        .font(.title3)
        .foregroundColor(.teal)
        .frame(width: 24, height: 24)
      
      VStack(alignment: .leading, spacing: 4) {
        Text(account.nickname)
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(Color.haloTextPrimary)
        
        Text(account.name)
          .font(.caption)
          .foregroundColor(Color.haloTextSecondary)
      }
      
      Spacer()
      
      VStack(alignment: .trailing, spacing: 4) {
        if account.isSynced {
          Text(account.balance.formatted(.currency(code: "USD")))
            .font(.body)
            .foregroundColor(account.balance >= 0 ? Color.haloPositive : Color.haloNegative)
        } else {
          Text("Not synced")
            .font(.caption)
            .foregroundColor(Color.haloTextSecondary)
        }
        
        Text(account.type.displayName)
          .font(.caption2)
          .foregroundColor(Color.haloTextSecondary)
      }
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 20)
    .background(Color.haloSecondaryBackground)
    .cornerRadius(16)
  }
}

#Preview("Account Detail Row") {
  ZStack {
    Color.haloBackground.ignoresSafeArea()
    AccountDetailRow(account: FinancialAccount(
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
