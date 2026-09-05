//
//  AccountDetailView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AccountDetailView: View {
  let account: FinancialAccount
  /// The raw bank account when opened from a linked institution; enables
  /// the Nickname button (manual accounts have their own editor).
  var bankAccount: BankAccount? = nil
  @State private var nicknameTarget: BankAccount?

  @Environment(BankDataManager.self) private var bankDataManager
  @Environment(UserManager.self) private var userManager
  @Environment(BudgetDataManager.self) private var budgetDataManager
  @State private var transactions: [Transaction] = []
  @State private var isLoadingInitial = false  // Only for first load with no cache
  @State private var transactionError: String?
  // Scales the balance with Dynamic Type instead of a fixed 32pt (App Store
  // Guideline 4 typography). minimumScaleFactor keeps big amounts on one line.
  @ScaledMetric(relativeTo: .largeTitle) private var balanceFontSize: CGFloat = 32

  var body: some View {
    ZStack {
      Color.haloBackground.ignoresSafeArea()

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
      if bankAccount != nil {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button { nicknameTarget = bankAccount } label: {
            Image(systemName: "pencil").frame(width: 44, height: 44)
          }
          .accessibilityLabel("Nickname")
          .accessibilityHint("Gives this account a name of your own.")
        }
      }
      ToolbarItem(placement: .navigationBarTrailing) {
        syncStatusIndicator
      }
    }
    .sheet(item: $nicknameTarget) { acct in
      AccountNicknameSheet(account: acct)
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
          .tint(Color.haloTextPrimary)
        Text("Syncing")
          .font(.caption)
          .foregroundColor(Color.haloTextSecondary)
      }
    } else if let lastSync = bankDataManager.lastTransactionSyncAt {
      Text(lastSync.relativeDescription)
        .font(.caption)
        .foregroundColor(Color.haloTextSecondary)
    }
  }
  
  @ViewBuilder
  private var contentView: some View {
    if isLoadingInitial && transactions.isEmpty {
      // Only show spinner for initial load with no cached data
      ProgressView()
        .tint(Color.haloTextPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let error = transactionError, transactions.isEmpty {
      // Only show error if we have no cached data to display
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
          .font(.largeTitle)
          .foregroundColor(.orange)
        Text(error)
          .foregroundColor(Color.haloTextSecondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 40)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if transactions.isEmpty && !isLoadingInitial {
      VStack(spacing: 12) {
        Image(systemName: "list.bullet.rectangle")
          .font(.largeTitle)
          .foregroundColor(Color.haloTextSecondary)
        Text("No transactions found")
          .foregroundColor(Color.haloTextSecondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      transactionsListView
    }
  }
  
  /// "Counted toward your SSI limit: yes / no", or the ABLE exclusion.
  private var ssiCountedLine: String {
    let kind = String(describing: account.type).lowercased()
    if kind.contains("credit") || kind.contains("loan") {
      return "Counted toward your SSI limit: no — this is money you owe. Estimate."
    }
    if account.name.lowercased().contains("able") || account.nickname.lowercased().contains("able") {
      return "ABLE account — excluded from your SSI limit up to 100,000 dollars. Estimate."
    }
    return "Counted toward your SSI limit: yes. Estimate."
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
            .foregroundColor(Color.haloTextPrimary)
          
          Text(account.name)
            .font(.subheadline)
            .foregroundColor(Color.haloTextSecondary)
        }
        
        Spacer()
      }
      
      Divider()
        .background(Color.haloSeparator)
      
      VStack(alignment: .leading, spacing: 8) {
        Text("Balance")
          .font(.caption)
          .foregroundColor(Color.haloTextSecondary)
        
        Text(account.balance, format: .currency(code: "USD"))
          .font(.system(size: balanceFontSize, weight: .bold))
          .minimumScaleFactor(0.6)
          .lineLimit(1)
          .foregroundColor(account.balance >= 0 ? Color.haloPositive : Color.haloNegative)
        
        HStack(spacing: 8) {
          Circle()
            .fill(account.isSynced ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
          
          Text(account.isSynced ? "Synced" : "Not Synced")
            .font(.caption)
            .foregroundColor(Color.haloTextSecondary)
        }

        // WP4 — SSI profiles hear whether this balance counts toward the
        // resource limit, and ABLE's exclusion, right under the balance.
        if userManager.capabilities.showsResourceCounter {
          Text(ssiCountedLine)
            .font(.caption)
            .foregroundColor(Color.haloTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(ssiCountedLine)
        }
      }
    }
    .padding(20)
    .background(Color.haloSecondaryBackground)
    .cornerRadius(16)
  }
  
  // MARK: - Transactions List View
  private var transactionsListView: some View {
    List {
      Section(header: Text("Transactions").foregroundColor(Color.haloTextSecondary)) {
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
        transactions = Self.sortedNewestFirst(MockTransactions.mockTransactions(for: account))
      } else if let plaidItemId = account.plaidItemId,
                let itemId = bankDataManager.getItemId(for: plaidItemId) {
        // Fetch recent transactions using cache-then-network pattern
        let fetched = try await bankDataManager.fetchRecentTransactions(
          accountId: account.id,
          itemId: itemId,
          limit: 50
        )
        transactions = Self.sortedNewestFirst(fetched)
      } else {
        // No plaidItemId or itemId available
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

  /// Newest-first by date. Plaid sometimes returns rows out of order
  /// (intra-day batches arrive grouped by category), and the older
  /// list relied on whatever order the cache returned. Authorized
  /// date is the truer transaction time when present; transactionDate
  /// (posting date) is the consistent fallback. Both come back as
  /// ISO YYYY-MM-DD or ISO 8601 datetime strings, which sort
  /// correctly as strings.
  private static func sortedNewestFirst(_ items: [Transaction]) -> [Transaction] {
    items.sorted { lhs, rhs in
      let lhsKey = lhs.authorizedDatetime ?? lhs.authorizedDate ?? lhs.transactionDatetime ?? lhs.transactionDate
      let rhsKey = rhs.authorizedDatetime ?? rhs.authorizedDate ?? rhs.transactionDatetime ?? rhs.transactionDate
      return lhsKey > rhsKey
    }
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
