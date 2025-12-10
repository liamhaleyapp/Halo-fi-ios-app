//
//  AccountDetailView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AccountDetailView: View {
  let account: FinancialAccount
  
  @Environment(BankDataManager.self) private var bankDataManager
  @State private var transactions: [Transaction] = []
  @State private var isLoadingTransactions = false
  @State private var transactionError: String?
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 0) {
        // Account Header
        accountHeaderView
          .padding(.top, 20)
          .padding(.bottom, 24)
        
        contentView
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadTransactions(forceRefresh: false)
    }
  }
  
  @ViewBuilder
  private var contentView: some View {
    if isLoadingTransactions {
      ProgressView()
        .tint(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let error = transactionError {
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
          .font(.largeTitle)
          .foregroundColor(.orange)
        Text(error)
          .foregroundColor(.gray)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 40)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if transactions.isEmpty {
      VStack(spacing: 12) {
        Image(systemName: "list.bullet.rectangle")
          .font(.largeTitle)
          .foregroundColor(.gray)
        Text("No transactions found")
          .foregroundColor(.gray)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      transactionsListView
    }
  }
  
  // MARK: - Account Header View
  private var accountHeaderView: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Image(systemName: account.type.icon)
          .font(.title)
          .foregroundColor(.teal)
          .frame(width: 50, height: 50)
          .background(Color.teal.opacity(0.2))
          .clipShape(Circle())
        
        VStack(alignment: .leading, spacing: 4) {
          Text(account.nickname)
            .font(.title2)
            .fontWeight(.bold)
            .foregroundColor(.white)
          
          Text(account.name)
            .font(.subheadline)
            .foregroundColor(.gray)
        }
        
        Spacer()
      }
      
      Divider()
        .background(Color.gray.opacity(0.3))
      
      VStack(alignment: .leading, spacing: 8) {
        Text("Balance")
          .font(.caption)
          .foregroundColor(.gray)
        
        Text(account.balance, format: .currency(code: "USD"))
          .font(.system(size: 32, weight: .bold))
          .foregroundColor(account.balance >= 0 ? .green : .red)
        
        HStack(spacing: 8) {
          Circle()
            .fill(account.isSynced ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
          
          Text(account.isSynced ? "Synced" : "Not Synced")
            .font(.caption)
            .foregroundColor(.gray)
        }
      }
    }
    .padding(20)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(16)
  }
  
  // MARK: - Transactions List View
  private var transactionsListView: some View {
    List {
      Section(header: Text("Transactions").foregroundColor(.gray)) {
        ForEach(transactions) { transaction in
          TransactionRow(transaction: transaction)
        }
      }
    }
    .listStyle(.insetGrouped)
    .refreshable {
      await loadTransactions(forceRefresh: true)
    }
  }
  
  // MARK: - Helper Methods
  private func loadTransactions(forceRefresh: Bool) async {
    if !forceRefresh {
      isLoadingTransactions = true
    }
    transactionError = nil
    
    do {
      if account.id.hasPrefix("mock-") {
        try await Task.sleep(nanoseconds: 500_000_000)
        transactions = MockTransactions.mockTransactions(for: account)
      } else {
        try await bankDataManager.fetchTransactions(accountId: account.id,
                                                    forceRefresh: forceRefresh)
        transactions = bankDataManager.getTransactions(for: account.id)
      }
    } catch {
      transactionError = "Failed to load transactions: \(error.localizedDescription)"
    }
    
    if !forceRefresh {
      isLoadingTransactions = false
    }
  }
}

#Preview("Account Detail - Checking") {
  NavigationView {
    AccountDetailView(account: FinancialAccount(
      id: "mock-checking-1",
      type: .checking,
      name: "Bank of America Checking",
      balance: 4502.32,
      nickname: "BofA Checking",
      isSynced: true
    ))
  }
}

#Preview("Account Detail - Credit Card") {
  NavigationView {
    AccountDetailView(account: FinancialAccount(
      id: "mock-credit-1",
      type: .creditCard,
      name: "Amex Platinum",
      balance: -1245.12,
      nickname: "Amex Platinum",
      isSynced: true
    ))
  }
}
