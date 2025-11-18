//
//  TransactionMocks.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 11/18/25.
//

import Foundation

enum MockTransactions {
  static func mockTransactions(for account: FinancialAccount,
                               count: Int = Int.random(in: 5...10)) -> [Transaction] {
    let baseDate = Date()
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    
    var mockTransactions: [Transaction] = []
    
    for i in 0..<count {
      guard let date = calendar.date(byAdding: .day,
                                     value: -(i * 2),
                                     to: baseDate) else { continue }
      
      let dateString = formatter.string(from: date)
      
      let (amount, name, merchantName, category) =
        mockTransactionFields(for: account.type, index: i)
      
      let transaction = Transaction(
        amount: amount,
        currency: "USD",
        transactionDate: dateString,
        name: name,
        merchantName: merchantName,
        category: category,
        pending: i == 0,
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
    
    return mockTransactions.sorted { $0.transactionDate > $1.transactionDate }
  }
  
  private static func mockTransactionFields(
    for type: AccountType,
    index i: Int
  ) -> (Double, String, String?, [String]) {
    switch type {
    case .checking:
      if i % 3 == 0 {
        let amount = Double.random(in: 2000...5000)
        return (amount, "Direct Deposit", nil, ["Transfer", "Payroll"])
      } else {
        let amount = -Double.random(in: 10...200)
        let merchants = ["Starbucks", "Amazon", "Target", "Whole Foods", "Uber"]
        let name = merchants.randomElement() ?? "Merchant"
        return (amount, name, name, ["Food and Drink", "Shops"])
      }
      
    case .creditCard:
      let amount = -Double.random(in: 20...500)
      let merchants = ["Amazon", "Target", "Best Buy", "Restaurant", "Gas Station"]
      let name = merchants.randomElement() ?? "Merchant"
      return (amount, name, name, ["Shops", "Food and Drink"])
      
    case .savings:
      if i % 2 == 0 {
        let amount = Double.random(in: 100...1000)
        return (amount, "Transfer", nil, ["Transfer"])
      } else {
        let amount = -Double.random(in: 50...500)
        return (amount, "Withdrawal", nil, ["Transfer"])
      }
      
    case .investment:
      let amount = Double.random(in: -500...1000)
      return (amount, "Investment Activity", nil, ["Investment"])
      
    case .loan:
      let amount = -Double.random(in: 200...1000)
      return (amount, "Loan Payment", nil, ["Loan Payment"])
    }
  }
}
