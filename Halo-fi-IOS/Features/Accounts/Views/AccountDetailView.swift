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
  @State private var isRefreshing = false
  @State private var transactionError: String?
  
  private var accountTransactions: [Transaction] {
    transactions.filter { $0.accountId == account.id }
  }
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 0) {
        // Account Header
        accountHeaderView
          .padding(.horizontal, 20)
          .padding(.top, 20)
          .padding(.bottom, 24)
        
        // Transactions List
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
        } else if accountTransactions.isEmpty {
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
    }
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadTransactions()
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
        ForEach(accountTransactions) { transaction in
          TransactionRow(transaction: transaction)
        }
      }
    }
    .listStyle(.insetGrouped)
    .refreshable {
      await refreshTransactions()
    }
  }
  
  // MARK: - Helper Methods
  private func loadTransactions() async {
    isLoadingTransactions = true
    transactionError = nil
    
    do {
      // Check if this is a mock account (starts with "mock-")
      if account.id.hasPrefix("mock-") {
        // Use mock transactions for demonstration
        try await Task.sleep(nanoseconds: 500_000_000) // Simulate network delay
        transactions = createMockTransactions(for: account)
      } else {
        // Fetch real transactions from API
        try await bankDataManager.fetchTransactions(accountId: account.id, forceRefresh: false)
        transactions = bankDataManager.getTransactions(for: account.id)
      }
      isLoadingTransactions = false
    } catch {
      transactionError = "Failed to load transactions: \(error.localizedDescription)"
      isLoadingTransactions = false
    }
  }
  
  private func refreshTransactions() async {
    isRefreshing = true
    transactionError = nil
    
    do {
      // Check if this is a mock account (starts with "mock-")
      if account.id.hasPrefix("mock-") {
        // Use mock transactions for demonstration
        try await Task.sleep(nanoseconds: 500_000_000) // Simulate network delay
        transactions = createMockTransactions(for: account)
      } else {
        // Fetch real transactions from API with force refresh
        try await bankDataManager.fetchTransactions(accountId: account.id, forceRefresh: true)
        transactions = bankDataManager.getTransactions(for: account.id)
      }
      isRefreshing = false
    } catch {
      transactionError = "Failed to refresh transactions: \(error.localizedDescription)"
      isRefreshing = false
    }
  }
  
  private func createMockTransactions(for account: FinancialAccount) -> [Transaction] {
    // Create mock transactions based on account type
    let baseDate = Date()
    let calendar = Calendar.current
    
    var mockTransactions: [Transaction] = []
    
    // Generate 5-10 mock transactions
    let transactionCount = Int.random(in: 5...10)
    
    for i in 0..<transactionCount {
      let daysAgo = i * 2
      guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: baseDate) else { continue }
      
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      let dateString = formatter.string(from: date)
      
      let amount: Double
      let name: String
      let merchantName: String?
      let category: [String]
      
      switch account.type {
      case .checking:
        if i % 3 == 0 {
          // Income
          amount = Double.random(in: 2000...5000)
          name = "Direct Deposit"
          merchantName = nil
          category = ["Transfer", "Payroll"]
        } else {
          // Expenses
          amount = -Double.random(in: 10...200)
          let merchants = ["Starbucks", "Amazon", "Target", "Whole Foods", "Uber"]
          name = merchants.randomElement() ?? "Merchant"
          merchantName = name
          category = ["Food and Drink", "Shops"]
        }
      case .creditCard:
        amount = -Double.random(in: 20...500)
        let merchants = ["Amazon", "Target", "Best Buy", "Restaurant", "Gas Station"]
        name = merchants.randomElement() ?? "Merchant"
        merchantName = name
        category = ["Shops", "Food and Drink"]
      case .savings:
        if i % 2 == 0 {
          amount = Double.random(in: 100...1000)
          name = "Transfer"
          merchantName = nil
          category = ["Transfer"]
        } else {
          amount = -Double.random(in: 50...500)
          name = "Withdrawal"
          merchantName = nil
          category = ["Transfer"]
        }
      case .investment:
        amount = Double.random(in: -500...1000)
        name = "Investment Activity"
        merchantName = nil
        category = ["Investment"]
      case .loan:
        amount = -Double.random(in: 200...1000)
        name = "Loan Payment"
        merchantName = nil
        category = ["Loan Payment"]
      }
      
      let transaction = Transaction(
        amount: amount,
        currency: "USD",
        transactionDate: dateString,
        name: name,
        merchantName: merchantName,
        category: category,
        pending: i == 0, // Most recent transaction is pending
        location: nil,
        paymentChannel: "other",
        transactionType: "place",
        transactionDatetime: nil,
        authorizedDate: nil,
        authorizedDatetime: nil,
        personalFinanceCategory: nil,
        personalFinanceCategoryIconUrl: nil,
        merchantEntityId: nil,
        logoUrl: nil,
        website: nil,
        counterparties: nil,
        pendingTransactionId: nil,
        checkNumber: nil,
        transactionCode: nil,
        idTransaction: "mock-transaction-\(account.id)-\(i)",
        accountId: account.id,
        plaidTransactionId: nil,
        isActive: true,
        lastSync: nil,
        createdAt: dateString + "T10:00:00Z",
        updatedAt: dateString + "T10:00:00Z"
      )
      
      mockTransactions.append(transaction)
    }
    
    // Sort by date, most recent first
    return mockTransactions.sorted { transaction1, transaction2 in
      transaction1.transactionDate > transaction2.transactionDate
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

