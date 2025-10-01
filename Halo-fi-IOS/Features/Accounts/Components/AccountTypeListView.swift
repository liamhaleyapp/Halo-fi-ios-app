//
//  AccountTypeListView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Account Type List View Component
struct AccountTypeListView: View {
    let accountType: AccountType
    
    private var accounts: [(name: String, balance: Double)] {
        MockAccountData.accounts(for: accountType)
    }
    
    private var title: String {
        MockAccountData.title(for: accountType)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                
                List {
                    Section(header: Text("Connected").foregroundColor(.gray)) {
                        ForEach(accounts.indices, id: \.self) { index in
                            AccountRowSimple(
                                name: accounts[index].name,
                                balance: accounts[index].balance
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview
#Preview("Checking Accounts") {
    NavigationView {
        AccountTypeListView(accountType: .checking)
    }
}

#Preview("Credit Cards") {
    NavigationView {
        AccountTypeListView(accountType: .creditCard)
    }
}

#Preview("Investments") {
    NavigationView {
        AccountTypeListView(accountType: .investment)
    }
}
