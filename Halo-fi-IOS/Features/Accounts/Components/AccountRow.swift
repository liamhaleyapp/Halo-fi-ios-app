//
//  AccountRow.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Account Row Component
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
                    .foregroundColor(.white)
                
                Text(account.type.displayName)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if account.isSynced {
                Text(account.balance.formatted(.currency(code: "USD")))
                    .font(.caption)
                    .foregroundColor(account.balance >= 0 ? .green : .red)
            } else {
                Text("Not synced")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Account Detail Row Component (for modal views)
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
                    .foregroundColor(.white)
                
                Text(account.name)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if account.isSynced {
                    Text(account.balance.formatted(.currency(code: "USD")))
                        .font(.body)
                        .foregroundColor(account.balance >= 0 ? .green : .red)
                } else {
                    Text("Not synced")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Text(account.type.displayName)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Previews
#Preview("Account Row") {
    ZStack {
        Color.black.ignoresSafeArea()
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

#Preview("Account Detail Row") {
    ZStack {
        Color.black.ignoresSafeArea()
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
