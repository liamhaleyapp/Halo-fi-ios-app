//
//  InstitutionCard.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct InstitutionCard: View {
  let institution: FinancialInstitution
  let onTap: () -> Void
  
  var body: some View {
    VStack(spacing: 0) {
      // Institution Header
      Button(action: onTap) {
        HStack(spacing: 16) {
          Image(systemName: institution.logo)
            .font(.title2)
            .foregroundColor(.teal)
            .frame(width: 32, height: 32)
          
          VStack(alignment: .leading, spacing: 4) {
            Text(institution.name)
              .font(.body)
              .fontWeight(.medium)
              .foregroundColor(.white)
            
            HStack(spacing: 8) {
              Circle()
                .fill(institution.status.color)
                .frame(width: 8, height: 8)
              
              Text(institution.status.displayText)
                .font(.caption)
                .foregroundColor(.gray)
            }
          }
          
          Spacer()
          
          Image(systemName: "chevron.right")
            .foregroundColor(.gray)
            .font(.caption)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
      }
      
      // Accounts Preview
      VStack(spacing: 6) {
        ForEach(institution.accounts.prefix(2)) { account in
          AccountRow(account: account)
        }
        
        if institution.accounts.count > 2 {
          HStack {
            Text("+\(institution.accounts.count - 2) more accounts")
              .font(.caption)
              .foregroundColor(.gray)
            Spacer()
          }
          .padding(.horizontal, 30)
          .padding(.vertical, 6)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 12)
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    InstitutionCard(
      institution: FinancialInstitution(
        id: "1",
        name: "Chase Bank",
        logo: "building.2.fill",
        status: .connected,
        accounts: [
          FinancialAccount(
            id: "1",
            type: .checking,
            name: "Chase Checking",
            balance: 2547.89,
            nickname: "Main Account",
            isSynced: true
          ),
          FinancialAccount(
            id: "2",
            type: .savings,
            name: "Chase Savings",
            balance: 12500.00,
            nickname: "Emergency Fund",
            isSynced: true
          )
        ]
      ),
      onTap: {}
    )
    .padding()
  }
}
