//
//  AccountTypeNavigationView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Account Type Navigation View
// This creates a proper navigation destination for each account type
struct AccountTypeNavigationView: View {
    let accountType: AccountType
    
    var body: some View {
        AccountTypeListView(accountType: accountType)
            .navigationTitle(MockAccountData.title(for: accountType))
            .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Convenience Extensions
extension AccountType {
    var navigationView: some View {
        AccountTypeNavigationView(accountType: self)
    }
}
