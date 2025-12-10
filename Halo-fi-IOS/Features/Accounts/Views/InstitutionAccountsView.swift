//
//  InstitutionAccountsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/4/25.
//

import SwiftUI

struct InstitutionAccountsView: View {
  @Environment(BankDataManager.self) private var bankDataManager
  let item: ConnectedItem
  
  @State private var accounts: [BankAccount]?
  @State private var isLoadingAccounts = false
  @State private var loadError: String?
  
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      ScrollView {
        VStack(spacing: 20) {
          // Institution Header
          institutionHeader
            .padding(.top, 20)
          
          // Content based on state
          if isLoadingAccounts {
            loadingView
          } else if let error = loadError {
            errorView(error)
          } else if let accounts = accounts {
            if accounts.isEmpty {
              emptyAccountsView
            } else {
              accountsListView(accounts)
            }
          } else {
            emptyAccountsView
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 100)
      }
    }
    .navigationTitle(item.institutionName)
    .navigationBarTitleDisplayMode(.large)
    .task {
      await loadAccounts()
    }
  }
  
  // MARK: - Institution Header
  
  private var institutionHeader: some View {
    VStack(spacing: 16) {
      HStack(spacing: 16) {
        Image(systemName: "building.2.fill")
          .font(.title)
          .foregroundColor(.teal)
          .frame(width: 40, height: 40)
          .accessibilityHidden(true)
        
        VStack(alignment: .leading, spacing: 4) {
          Text(item.institutionName)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
          
          HStack(spacing: 8) {
            Circle()
              .fill(item.isActive ? Color.green : Color.orange)
              .frame(width: 8, height: 8)
              .accessibilityLabel(item.isActive ? "Connected" : "Needs Attention")
            
            Text(item.isActive ? "Connected" : "Needs Attention")
              .font(.subheadline)
              .foregroundColor(.gray)
          }
        }
        
        Spacer()
      }
      
      if let accounts = accounts, !accounts.isEmpty {
        Divider()
          .background(Color.gray.opacity(0.3))
        
        let totalBalance = accounts.reduce(0) { $0 + $1.currentBalance }
        let currency = accounts.first?.currency ?? "USD"
        
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Total Balance")
              .font(.caption)
              .foregroundColor(.gray)
            
            Text(CurrencyFormatter.format(totalBalance, currency: currency))
              .font(.title3)
              .fontWeight(.bold)
              .foregroundColor(.white)
          }
          
          Spacer()
          
          VStack(alignment: .trailing, spacing: 4) {
            Text("Accounts")
              .font(.caption)
              .foregroundColor(.gray)
            
            Text("\(accounts.count)")
              .font(.title3)
              .fontWeight(.bold)
              .foregroundColor(.white)
          }
        }
      }
    }
    .padding(20)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(16)
  }
  
  // MARK: - Accounts List View
  
  private func accountsListView(_ accounts: [BankAccount]) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Accounts")
        .font(.headline)
        .foregroundColor(.gray)
        .accessibilityAddTraits(.isHeader)
        .padding(.top, 8)
      
      ForEach(accounts, id: \.id) { account in
        BankAccountRow(account: account)
      }
    }
  }
  
  // MARK: - Loading View
  
  private var loadingView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.2)
        .tint(.white)
        .accessibilityLabel("Loading accounts")
      
      Text("Loading accounts...")
        .font(.body)
        .foregroundColor(.gray)
        .accessibilityLabel("Loading accounts, please wait")
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }
  
  // MARK: - Error View
  
  private func errorView(_ error: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))
        .foregroundColor(.orange)
        .accessibilityHidden(true)
      
      Text("Error Loading Accounts")
        .font(.headline)
        .foregroundColor(.white)
        .accessibilityAddTraits(.isHeader)
      
      Text(error)
        .font(.subheadline)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
        .accessibilityLabel("Error: \(error)")
      
      Button {
        Task {
          await loadAccounts()
        }
      } label: {
        Text("Retry")
          .font(.body)
          .fontWeight(.semibold)
          .foregroundColor(.white)
          .padding(.horizontal, 24)
          .padding(.vertical, 12)
          .background(Color.blue)
          .cornerRadius(12)
      }
      .accessibilityLabel("Retry loading accounts")
      .accessibilityHint("Double tap to attempt loading accounts again")
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }
  
  // MARK: - Empty Accounts View
  
  private var emptyAccountsView: some View {
    VStack(spacing: 16) {
      Image(systemName: "creditcard")
        .font(.system(size: 48))
        .foregroundColor(.gray.opacity(0.5))
        .accessibilityHidden(true)
      
      Text("No Accounts Found")
        .font(.headline)
        .foregroundColor(.white)
        .accessibilityAddTraits(.isHeader)
      
      Text("No accounts were found for this institution")
        .font(.subheadline)
        .foregroundColor(.gray)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }
  
  // MARK: - Data Loading
  
  private func loadAccounts() async {
    // Check if we already have accounts cached
    if let cachedAccounts = bankDataManager.accountsByItemId[item.itemId] {
      await MainActor.run {
        self.accounts = cachedAccounts
        self.isLoadingAccounts = false
      }
      return
    }
    
    await MainActor.run {
      isLoadingAccounts = true
      loadError = nil
    }
    
    do {
      Logger.info("InstitutionAccountsView: Fetching accounts for item \(item.itemId) (\(item.institutionName))")
      let response = try await bankDataManager.fetchAccountsForItem(itemId: item.itemId)
      
      await MainActor.run {
        bankDataManager.accountsByItemId[item.itemId] = response.accounts
        self.accounts = response.accounts
        self.isLoadingAccounts = false
        Logger.success("InstitutionAccountsView: Fetched \(response.accounts.count) accounts for \(item.institutionName)")
      }
    } catch {
      await MainActor.run {
        isLoadingAccounts = false
        loadError = "Failed to load accounts: \(error.localizedDescription)"
        Logger.error("InstitutionAccountsView: Error fetching accounts: \(error)")
      }
    }
  }
}

// MARK: - Bank Account Row

struct BankAccountRow: View {
  let account: BankAccount
  
  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: accountIcon(for: account.type))
        .font(.title3)
        .foregroundColor(.teal)
        .frame(width: 24, height: 24)
      
      VStack(alignment: .leading, spacing: 4) {
        Text(account.name)
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(.white)
        
        HStack(spacing: 4) {
          Text(account.type.capitalized)
            .font(.caption)
            .foregroundColor(.gray)
          
          if !account.mask.isEmpty {
            Text("•")
              .font(.caption)
              .foregroundColor(.gray)
            
            Text("ending in \(account.mask)")
              .font(.caption)
              .foregroundColor(.gray)
          }
        }
      }
      
      Spacer()
      
      VStack(alignment: .trailing, spacing: 4) {
        Text(CurrencyFormatter.format(account.currentBalance, currency: account.currency))
          .font(.body)
          .foregroundColor(account.currentBalance >= 0 ? .green : .red)

        if account.isActive {
          Text("Active")
            .font(.caption2)
            .foregroundColor(.gray)
        } else {
          Text("Inactive")
            .font(.caption2)
            .foregroundColor(.orange)
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(16)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(account.name), \(account.type.capitalized), ending in \(account.mask), Balance \(CurrencyFormatter.format(account.currentBalance, currency: account.currency))")
  }

  private func accountIcon(for type: String) -> String {
    switch type.lowercased() {
    case "depository":
      return "building.columns.fill"
    case "credit":
      return "creditcard.fill"
    case "loan":
      return "doc.text.fill"
    case "investment":
      return "chart.line.uptrend.xyaxis"
    default:
      return "wallet.pass.fill"
    }
  }
}

#Preview {
  NavigationStack {
    InstitutionAccountsView(
      item: ConnectedItem(
        institutionId: "ins_1",
        institutionName: "Chase Bank",
        availableProducts: nil,
        itemId: "item_1",
        userId: "user_1",
        plaidItemId: "plaid_1",
        isActive: true,
        lastSync: nil,
        createdAt: nil,
        updatedAt: nil
      )
    )
    .environment(BankDataManager())
  }
}
