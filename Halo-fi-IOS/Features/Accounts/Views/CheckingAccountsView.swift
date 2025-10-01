//
//  CheckingAccountsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct CheckingAccountsView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Checking Accounts")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                
                List {
                    Section(header: Text("Connected").foregroundColor(.gray)) {
                        AccountRowSimple(name: "Bank of America Checking", balance: 4502.32)
                        AccountRowSimple(name: "Chime Checking", balance: 1120.00)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountRowSimple: View {
    let name: String
    let balance: Double
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .foregroundColor(.white)
                Text("Checking")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            Text(balance, format: .currency(code: "USD"))
                .foregroundColor(balance >= 0 ? .green : .red)
        }
        .listRowBackground(Color.gray.opacity(0.15))
    }
}

#Preview {
    NavigationView { CheckingAccountsView() }
}



