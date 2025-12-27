//
//  AccessibleInstitutionCard.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/4/25.
//

import SwiftUI

// MARK: - Main Card View

struct AccessibleInstitutionCard: View {
  let item: ConnectedItem
  let accounts: [BankAccount]?
  let isLoading: Bool
  
  // MARK: - Computed Properties
  
  private var totalBalance: Double {
    accounts?.reduce(0) { $0 + $1.currentBalance } ?? 0
  }
  
  private var currency: String {
    accounts?.first?.currency ?? "USD"
  }
  
  private var accessibilityLabel: String {
    var label = item.institutionName
    label += item.isActive ? ", Connected" : ", Needs Attention"
    
    if let accounts = accounts {
      let count = accounts.count
      label += ", \(count) account\(count == 1 ? "" : "s")"
      if !accounts.isEmpty {
        label += ", Total balance \(CurrencyFormatter.format(totalBalance, currency: currency))"
      }
    } else if isLoading {
      label += ", Loading accounts"
    }
    
    return label
  }
  
  private var accessibilityHint: String {
    accounts != nil
      ? "Double tap to view all accounts for \(item.institutionName)"
      : "Double tap to load accounts for \(item.institutionName)"
  }
  
  // MARK: - Body
  
  var body: some View {
    InstitutionHeaderView(
      item: item,
      accounts: accounts,
      totalBalance: totalBalance,
      currency: currency,
      isLoading: isLoading
    )
    .background(Color.gray.opacity(0.05))
    .cornerRadius(16)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(accessibilityHint)
  }
}

// MARK: - Institution Header View

private struct InstitutionHeaderView: View {
  let item: ConnectedItem
  let accounts: [BankAccount]?
  let totalBalance: Double
  let currency: String
  let isLoading: Bool
  
  var body: some View {
    HStack(spacing: 16) {
      institutionIcon
      institutionDetails
      Spacer()
      trailingIndicator
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(16)
  }
  
  private var institutionIcon: some View {
    Image(systemName: "building.2.fill")
      .font(.title2)
      .foregroundColor(.teal)
      .frame(width: 32, height: 32)
      .accessibilityHidden(true)
  }
  
  private var institutionDetails: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(item.institutionName)
        .font(.body)
        .fontWeight(.medium)
        .foregroundColor(.white)
      
      ConnectionStatusBadge(isActive: item.isActive)
      
      AccountSummaryLabel(
        accounts: accounts,
        totalBalance: totalBalance,
        currency: currency,
        isLoading: isLoading
      )
    }
  }
  
  @ViewBuilder
  private var trailingIndicator: some View {
    if isLoading {
      ProgressView()
        .scaleEffect(0.8)
        .accessibilityHidden(true)
    } else {
      Image(systemName: "chevron.right")
        .foregroundColor(.gray)
        .font(.caption)
        .accessibilityHidden(true)
    }
  }
}

// MARK: - Connection Status Badge

private struct ConnectionStatusBadge: View {
  let isActive: Bool
  
  private var statusColor: Color {
    isActive ? .green : .orange
  }
  
  private var statusText: String {
    isActive ? "Connected" : "Needs Attention"
  }
  
  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)
      
      Text(statusText)
        .font(.caption)
        .foregroundColor(.gray)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(statusText)
  }
}

// MARK: - Account Summary Label

private struct AccountSummaryLabel: View {
  let accounts: [BankAccount]?
  let totalBalance: Double
  let currency: String
  let isLoading: Bool
  
  var body: some View {
    Group {
      if let accounts = accounts, !accounts.isEmpty {
        accountsLoadedContent(count: accounts.count)
      } else if isLoading {
        loadingContent
      }
    }
  }
  
  private func accountsLoadedContent(count: Int) -> some View {
    HStack(spacing: 8) {
      Text("\(count) account\(count == 1 ? "" : "s")")
        .font(.caption)
        .foregroundColor(.gray)
      
      Text("•")
        .font(.caption)
        .foregroundColor(.gray)
      
      Text(CurrencyFormatter.format(totalBalance, currency: currency))
        .font(.caption)
        .fontWeight(.medium)
        .foregroundColor(.white.opacity(0.8))
    }
  }
  
  private var loadingContent: some View {
    HStack(spacing: 8) {
      ProgressView()
        .scaleEffect(0.7)
      
      Text("Loading accounts...")
        .font(.caption)
        .foregroundColor(.gray)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Loading accounts")
  }
}

// Uses CurrencyFormatter from Shared/Helpers/CurrencyFormatter.swift

// MARK: - Preview

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VStack {
      AccessibleInstitutionCard(
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
        ),
        accounts: [
          BankAccount(
            name: "Checking Account",
            mask: "1234",
            type: "depository",
            subtype: "checking",
            currentBalance: 1234.56,
            availableBalance: 1234.56,
            currency: "USD",
            idAccount: "acc_1",
            plaidItemId: "item_1",
            plaidAccountId: "plaid_acc_1",
            isActive: true,
            createdAt: "",
            updatedAt: ""
          )
        ],
        isLoading: false
      )
      .padding()
    }
  }
}
