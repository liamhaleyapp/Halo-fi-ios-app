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
  @State private var isLoadingInitial = false  // Only for first load with no cache
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
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        syncStatusIndicator
      }
    }
    .task {
      await loadTransactions(forceRefresh: false)
    }
  }

  // MARK: - Sync Status Indicator
  @ViewBuilder
  private var syncStatusIndicator: some View {
    if bankDataManager.isSyncing {
      HStack(spacing: 4) {
        ProgressView()
          .scaleEffect(0.7)
          .tint(.white)
        Text("Syncing")
          .font(.caption)
          .foregroundColor(.gray)
      }
    } else if let lastSync = bankDataManager.lastTransactionSyncAt {
      Text(lastSync.relativeDescription)
        .font(.caption)
        .foregroundColor(.gray)
    }
  }
  
  @ViewBuilder
  private var contentView: some View {
    if isLoadingInitial && transactions.isEmpty {
      // Only show spinner for initial load with no cached data
      ProgressView()
        .tint(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let error = transactionError, transactions.isEmpty {
      // Only show error if we have no cached data to display
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
    } else if transactions.isEmpty && !isLoadingInitial {
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
    // Only show initial loading spinner if we have no cached transactions
    let hasCachedData = !transactions.isEmpty

    if !hasCachedData && !forceRefresh {
      isLoadingInitial = true
    }
    transactionError = nil

    do {
      // Use mock transactions for mock accounts
      if account.id.hasPrefix("mock-") {
        try await Task.sleep(nanoseconds: 500_000_000)
        transactions = MockTransactions.mockTransactions(for: account)
      } else if let plaidItemId = account.plaidItemId {
        // Fetch recent transactions using cache-then-network pattern
        let fetched = try await bankDataManager.fetchRecentTransactions(
          accountId: account.id,
          plaidItemId: plaidItemId,
          limit: 50
        )
        transactions = fetched
      } else {
        // No plaidItemId available
        transactions = []
      }
    } catch {
      // Only show error if we have no cached data to display
      if transactions.isEmpty {
        transactionError = "Failed to load transactions: \(error.localizedDescription)"
      }
    }

    isLoadingInitial = false
  }
}

#Preview("Account Detail - Checking") {
  NavigationStack {
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
  NavigationStack {
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
