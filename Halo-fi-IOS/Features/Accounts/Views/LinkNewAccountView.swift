//
//  LinkNewAccountView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct LinkNewAccountView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var searchText = ""
  @State private var selectedBank: String?
  
  let popularBanks = ["Chase", "Bank of America", "Wells Fargo", "Citibank", "Capital One", "American Express"]
  
  var body: some View {
    NavigationView {
      ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 20) {
          Text("Link New Account")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.top, 20)
          
          VStack(alignment: .leading, spacing: 12) {
            Text("Search for your bank")
              .font(.body)
              .foregroundColor(.white)
            
            TextField("Enter bank name...", text: $searchText)
              .textFieldStyle(.roundedBorder)
          }
          .padding(.horizontal, 20)
          
          VStack(alignment: .leading, spacing: 12) {
            Text("Popular Banks")
              .font(.headline)
              .foregroundColor(.gray)
              .padding(.horizontal, 20)
            
            ForEach(popularBanks, id: \.self) { bank in
              Button(action: {
                selectedBank = bank
              }) {
                HStack {
                  Text(bank)
                    .font(.body)
                    .foregroundColor(.white)
                  Spacer()
                  if selectedBank == bank {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundColor(.teal)
                  }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
                .background(selectedBank == bank ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(12)
              }
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
