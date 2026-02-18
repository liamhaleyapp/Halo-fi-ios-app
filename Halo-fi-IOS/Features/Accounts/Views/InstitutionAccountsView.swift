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
    .navigationTitle(item.institutionName)
    .navigationBarTitleDisplayMode(.large)
    .task {
      await loadAccounts()
    }
  }

  // MARK: - Accounts List View

  private func accountsListView(_ accounts: [BankAccount]) -> some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        ForEach(accounts, id: \.id) { account in
          NavigationLink {
            AccountDetailView(account: FinancialAccount(from: account, plaidItemId: item.plaidItemId))
              .environment(bankDataManager)
          } label: {
            BankAccountRow(account: account)
          }
          .buttonStyle(HapticPlainButtonStyle())
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .padding(.bottom, 100)
    }
  }

  // MARK: - Loading View

  private var loadingView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.2)
        .tint(.white)

      Text("Loading accounts...")
        .font(.body)
        .foregroundColor(.gray)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Loading accounts, please wait")
  }

  // MARK: - Error View

  private func errorView(_ error: String) -> some View {
    VStack(spacing: 20) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))
        .foregroundColor(.orange)
        .accessibilityHidden(true)

      VStack(spacing: 8) {
        Text("Couldn't Load Accounts")
          .font(.title3)
          .fontWeight(.semibold)
          .foregroundColor(.white)

        Text(error)
          .font(.body)
          .foregroundColor(.gray)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 40)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Couldn't load accounts. \(error)")

      Button {
        Task {
          await loadAccounts()
        }
      } label: {
        Text("Retry")
          .font(.body)
          .fontWeight(.semibold)
          .foregroundColor(.white)
          .padding(.horizontal, 32)
          .padding(.vertical, 14)
          .background(Color.blue)
          .cornerRadius(12)
      }
      .accessibilityLabel("Retry")
      .accessibilityHint("Double tap to try loading accounts again")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Empty Accounts View

  private var emptyAccountsView: some View {
    EmptyStateView(
      icon: "creditcard",
      title: "No Accounts Found",
      message: "No accounts were found for this institution"
    )
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
        loadError = "Failed to load accounts. Please try again."
        Logger.error("InstitutionAccountsView: Error fetching accounts: \(error)")
      }
    }
  }
}

// MARK: - Bank Account Row

struct BankAccountRow: View {
  let account: BankAccount

  private var accessibilityLabel: String {
    var label = account.name

    if !account.mask.isEmpty {
      label += ", ending in \(account.mask)"
    }

    // Use appropriate wording based on account type
    if account.type.lowercased() == "credit" {
      label += ", Amount owed \(CurrencyFormatter.format(abs(account.currentBalance), currency: account.currency))"
    } else {
      label += ", Balance \(CurrencyFormatter.format(account.currentBalance, currency: account.currency))"
    }

    return label
  }

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: accountIcon(for: account.type))
        .font(.title3)
        .foregroundColor(.teal)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)

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

      Text(CurrencyFormatter.format(account.currentBalance, currency: account.currency))
        .font(.body)
        .fontWeight(.medium)
        .foregroundColor(account.currentBalance >= 0 ? .green : .red)

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(.gray)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(16)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint("Double tap to view transactions")
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
