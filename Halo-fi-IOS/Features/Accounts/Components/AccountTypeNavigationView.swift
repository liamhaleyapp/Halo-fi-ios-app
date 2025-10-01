//
//  AccountTypeNavigationView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AccountTypeNavigationView: View {
  let accountType: AccountType
  
  var body: some View {
    AccountTypeListView(accountType: accountType)
      .navigationTitle(MockAccountData.title(for: accountType))
      .navigationBarTitleDisplayMode(.large)
  }
}

extension AccountType {
  var navigationView: some View {
    AccountTypeNavigationView(accountType: self)
  }
}
