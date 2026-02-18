//
//  TransactionRow.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct TransactionRow: View {
  let transaction: Transaction

  private var displayName: String {
    transaction.merchantName ?? transaction.name
  }

  private var categoryName: String {
    if let categories = transaction.category, !categories.isEmpty {
      return categories.joined(separator: " • ")
    }
    return "Uncategorized"
  }

  private var formattedDate: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    if let date = formatter.date(from: transaction.transactionDate) {
      formatter.dateFormat = "MMM d"
      return formatter.string(from: date)
    }

    return transaction.transactionDate
  }

  private var accessibilityLabel: String {
    var label = displayName

    // Amount with appropriate sign description
    let formattedAmount = transaction.amount.formatted(.currency(code: transaction.currency))
    if transaction.amount >= 0 {
      label += ", Received \(formattedAmount)"
    } else {
      label += ", Spent \(formattedAmount.replacingOccurrences(of: "-", with: ""))"
    }

    // Date
    label += ", \(formattedDate)"

    // Pending status
    if transaction.pending {
      label += ", Pending"
    }

    return label
  }
  
  var body: some View {
    HStack(spacing: 16) {
      // Transaction icon/indicator
      Circle()
        .fill(transaction.amount >= 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
        .frame(width: 40, height: 40)
        .overlay(
          Image(systemName: transaction.amount >= 0 ? "arrow.down" : "arrow.up")
            .font(.caption)
            .foregroundColor(transaction.amount >= 0 ? .green : .red)
        )
      
      VStack(alignment: .leading, spacing: 4) {
        Text(displayName)
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(.white)
          .lineLimit(1)
        
        HStack(spacing: 8) {
          Text(categoryName)
            .font(.caption)
            .foregroundColor(.gray)
          
          if transaction.pending {
            Text("• Pending")
              .font(.caption)
              .foregroundColor(.orange)
          }
        }
      }
      
      Spacer()
      
      VStack(alignment: .trailing, spacing: 4) {
        Text(transaction.amount, format: .currency(code: transaction.currency))
          .font(.body)
          .fontWeight(.semibold)
          .foregroundColor(transaction.amount >= 0 ? .green : .red)
        
        Text(formattedDate)
          .font(.caption)
          .foregroundColor(.gray)
      }
    }
    .padding(.vertical, 12)
    .listRowBackground(Color.gray.opacity(0.15))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }
}

#Preview("Transaction Row - Debit") {
  ZStack {
    Color.black.ignoresSafeArea()
    List {
      TransactionRow(transaction: Transaction(
        amount: -45.99,
        currency: "USD",
        transactionDate: "2025-10-15",
        name: "Starbucks",
        merchantName: "Starbucks Store #1234",
        category: ["Food and Drink", "Restaurants"],
        pending: false,
        location: nil,
        paymentChannel: "in store",
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
        idTransaction: "1",
        accountId: "account-1",
        plaidTransactionId: nil,
        isActive: true,
        lastSync: nil,
        createdAt: "2025-10-15T10:00:00Z",
        updatedAt: "2025-10-15T10:00:00Z"
      ))
    }
    .listStyle(.insetGrouped)
  }
}

#Preview("Transaction Row - Credit") {
  ZStack {
    Color.black.ignoresSafeArea()
    List {
      TransactionRow(transaction: Transaction(
        amount: 2500.00,
        currency: "USD",
        transactionDate: "2025-10-01",
        name: "Direct Deposit",
        merchantName: nil,
        category: ["Transfer", "Payroll"],
        pending: false,
        location: nil,
        paymentChannel: "other",
        transactionType: "special",
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
        idTransaction: "2",
        accountId: "account-1",
        plaidTransactionId: nil,
        isActive: true,
        lastSync: nil,
        createdAt: "2025-10-01T08:00:00Z",
        updatedAt: "2025-10-01T08:00:00Z"
      ))
    }
    .listStyle(.insetGrouped)
  }
}

#Preview("Transaction Row - Pending") {
  ZStack {
    Color.black.ignoresSafeArea()
    List {
      TransactionRow(transaction: Transaction(
        amount: -89.50,
        currency: "USD",
        transactionDate: "2025-10-20",
        name: "Amazon",
        merchantName: "Amazon.com",
        category: ["Shops", "Superstores"],
        pending: true,
        location: nil,
        paymentChannel: "online",
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
        idTransaction: "3",
        accountId: "account-1",
        plaidTransactionId: nil,
        isActive: true,
        lastSync: nil,
        createdAt: "2025-10-20T14:00:00Z",
        updatedAt: "2025-10-20T14:00:00Z"
      ))
    }
    .listStyle(.insetGrouped)
  }
}
