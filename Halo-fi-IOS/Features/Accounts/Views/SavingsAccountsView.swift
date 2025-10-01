//
//  SavingsAccountsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SavingsAccountsView: View {
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 16) {
        Text("Savings Accounts")
          .font(.largeTitle)
          .fontWeight(.heavy)
          .foregroundColor(.white)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 12)
        
        List {
          Section(header: Text("Connected").foregroundColor(.gray)) {
            AccountRowSimple(name: "Ally Savings", balance: 9230.50)
          }
        }
        .listStyle(.insetGrouped)
      }
      .padding(.horizontal, 20)
    }
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationView { SavingsAccountsView() }
}



