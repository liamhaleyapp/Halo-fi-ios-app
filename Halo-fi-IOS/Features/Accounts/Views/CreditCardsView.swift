//
//  CreditCardsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct CreditCardsView: View {
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 16) {
        Text("Credit Cards")
          .font(.largeTitle)
          .fontWeight(.heavy)
          .foregroundColor(.white)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 12)
        
        List {
          Section(header: Text("Connected").foregroundColor(.gray)) {
            AccountRowSimple(name: "Amex Platinum", balance: -1245.12)
            AccountRowSimple(name: "Chase Sapphire", balance: -3010.00)
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
  NavigationView { CreditCardsView() }
}



