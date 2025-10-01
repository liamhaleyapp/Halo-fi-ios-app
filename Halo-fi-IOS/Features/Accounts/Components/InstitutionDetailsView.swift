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
    NavigationView {
      ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 20) {
          Text(institution.name)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.top, 20)
          
          VStack(alignment: .leading, spacing: 16) {
            HStack {
              Image(systemName: institution.logo)
                .font(.title)
                .foregroundColor(.teal)
              
              VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                  .font(.caption)
                  .foregroundColor(.gray)
                
                HStack(spacing: 8) {
                  Circle()
                    .fill(institution.status.color)
                    .frame(width: 8, height: 8)
                  
                  Text(institution.status.displayText)
                    .font(.body)
                    .foregroundColor(.white)
                }
              }
              
              Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            
            Text("Accounts")
              .font(.headline)
              .foregroundColor(.gray)
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
          .foregroundColor(.white)
        }
      }
    }
  }
}
