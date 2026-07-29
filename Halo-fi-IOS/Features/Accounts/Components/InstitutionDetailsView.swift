//
//  InstitutionDetailsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct InstitutionDetailsView: View {
  @Environment(\.dismiss) private var dismiss
  let institution: FinancialInstitution
  
  var body: some View {
    NavigationStack {
      ZStack {
        Color.haloBackground.ignoresSafeArea()
        
        VStack(spacing: 20) {
          Text(institution.name)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(Color.haloTextPrimary)
            .padding(.top, 20)
          
          VStack(alignment: .leading, spacing: 16) {
            HStack {
              Image(systemName: institution.logo)
                .font(.title)
                .foregroundColor(.teal)
              
              VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                  .font(.caption)
                  .foregroundColor(Color.haloTextSecondary)
                
                HStack(spacing: 8) {
                  Circle()
                    .fill(institution.status.color)
                    .frame(width: 8, height: 8)
                  
                  Text(institution.status.displayText)
                    .font(.body)
                    .foregroundColor(Color.haloTextPrimary)
                }
              }
              
              Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.haloSecondaryBackground)
            .cornerRadius(16)
            
            Text("Accounts")
              .font(.headline)
              .foregroundColor(Color.haloTextSecondary)
              .padding(.horizontal, 20)
            
            ForEach(institution.accounts) { account in
              AccountDetailRow(account: account)
            }
          }
          
          Spacer()
        }
      }
      .navigationBarHidden(true)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
          .foregroundColor(Color.haloTextPrimary)
        }
      }
    }
  }
}
