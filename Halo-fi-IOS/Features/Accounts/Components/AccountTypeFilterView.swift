//
//  AccountTypeFilterView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/4/25.
//

import SwiftUI

struct AccountTypeFilterView: View {
  @Environment(BankDataManager.self) private var bankDataManager
  
  let accountsByType: [String: [BankAccount]]
  
  private var accountTypes: [AccountType] {
    [.checking, .savings, .creditCard, .investment, .loan]
  }
  
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        ForEach(accountTypes, id: \.self) { accountType in
          if let accounts = accountsForType(accountType), !accounts.isEmpty {
            AccountTypeSection(
              accountType: accountType,
              accounts: accounts
            )
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .padding(.bottom, 100)
    }
  }
  
  private func accountsForType(_ type: AccountType) -> [BankAccount]? {
    // Map AccountType to possible Plaid type strings
    let typeStrings = typeStringsForAccountType(type)
    var matchingAccounts: [BankAccount] = []
    
    for (key, accounts) in accountsByType {
      if typeStrings.contains(key.lowercased()) {
        matchingAccounts.append(contentsOf: accounts)
      }
    }
    
    return matchingAccounts.isEmpty ? nil : matchingAccounts
  }
  
  private func typeStringsForAccountType(_ type: AccountType) -> [String] {
    switch type {
    case .checking:
      return ["depository", "checking"]
    case .savings:
      return ["depository", "savings"]
    case .creditCard:
      return ["credit"]
    case .investment:
      return ["investment", "brokerage"]
    case .loan:
      return ["loan"]
    }
  }
}

// MARK: - Account Type Section

struct AccountTypeSection: View {
  let accountType: AccountType
  let accounts: [BankAccount]
  
  private var totalBalance: Double {
    accounts.reduce(0) { $0 + $1.currentBalance }
  }
  
  private var currency: String {
    accounts.first?.currency ?? "USD"
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Section Header
      HStack {
        Image(systemName: accountType.icon)
          .font(.title3)
          .foregroundColor(.teal)
          .frame(width: 32, height: 32)
          .accessibilityHidden(true)
        
        VStack(alignment: .leading, spacing: 4) {
          Text(accountType.displayName)
            .font(.headline)
            .foregroundColor(.white)
            .accessibilityAddTraits(.isHeader)
          
          Text("\(accounts.count) account\(accounts.count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundColor(.gray)
        }
        
        Spacer()
        
        Text(formatCurrency(totalBalance, currency: currency))
          .font(.headline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
          .accessibilityLabel("Total balance, \(formatCurrency(totalBalance, currency: currency))")
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .background(Color.gray.opacity(0.1))
      .cornerRadius(12)
      
      // Accounts List
      VStack(spacing: 8) {
        ForEach(accounts, id: \.id) { account in
          AccountTypeRow(
            account: account,
            showInstitution: true
          )
        }
      }
    }
    .background(Color.gray.opacity(0.05))
    .cornerRadius(16)
    .padding(.bottom, 8)
  }
  
  private func formatCurrency(_ amount: Double, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
  }
}

// MARK: - Account Type Row

struct AccountTypeRow: View {
  let account: BankAccount
  let showInstitution: Bool
  
  // Get institution name from BankDataManager if needed
  @Environment(BankDataManager.self) private var bankDataManager
  
  private var institutionName: String? {
    guard showInstitution else { return nil }
    // Find the institution for this account
    for (itemId, accounts) in bankDataManager.accountsByItemId {
      if accounts.contains(where: { $0.id == account.id }) {
        return bankDataManager.linkedItems?.first(where: { $0.itemId == itemId })?.institutionName
      }
    }
    return nil
  }
  
  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(account.name)
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.white)
        
        HStack(spacing: 8) {
          if let institutionName = institutionName {
            Text(institutionName)
              .font(.caption)
              .foregroundColor(.gray)
            Text("•")
              .font(.caption)
              .foregroundColor(.gray)
          }
          Text("\(account.type.capitalized) ••••\(account.mask)")
            .font(.caption)
            .foregroundColor(.gray)
        }
      }
      
      Spacer()
      
      Text(formatCurrency(account.currentBalance, currency: account.currency))
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(.white)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .background(Color.gray.opacity(0.05))
    .cornerRadius(12)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }
  
  private var accessibilityLabel: String {
    var label = account.name
    if let institutionName = institutionName {
      label += ", \(institutionName)"
    }
    label += ", \(account.type.capitalized), ending in \(account.mask)"
    label += ", Balance \(formatCurrency(account.currentBalance, currency: account.currency))"
    return label
  }
  
  private func formatCurrency(_ amount: Double, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    AccountTypeFilterView(
      accountsByType: [
        "depository": [
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
        ]
      ]
    )
    .environment(BankDataManager())
  }
}

