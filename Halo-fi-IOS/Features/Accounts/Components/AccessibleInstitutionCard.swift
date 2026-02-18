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

  private var accessibilityLabel: String {
    var label = item.institutionName
    label += ". " // Period for natural pause

    // Status
    label += item.isActive ? "Connected" : "Needs attention"

    // Account count
    if let accounts = accounts, !accounts.isEmpty {
      let count = accounts.count
      label += ". \(count) account\(count == 1 ? "" : "s")"
    } else if isLoading {
      label += ". Loading accounts"
    }

    return label
  }

  private var accessibilityHint: String {
    "Double tap to view accounts"
  }

  // MARK: - Body

  var body: some View {
    HStack(spacing: 16) {
      // Institution icon
      Image(systemName: "building.2.fill")
        .font(.title2)
        .foregroundColor(.teal)
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)

      // Institution details
      VStack(alignment: .leading, spacing: 6) {
        Text(item.institutionName)
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(.white)

        // Status indicator
        HStack(spacing: 8) {
          Circle()
            .fill(item.isActive ? Color.green : Color.orange)
            .frame(width: 8, height: 8)

          Text(item.isActive ? "Connected" : "Needs attention")
            .font(.caption)
            .foregroundColor(.gray)
        }

        // Account count (if available)
        if let accounts = accounts, !accounts.isEmpty {
          Text("\(accounts.count) account\(accounts.count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundColor(.gray.opacity(0.8))
        } else if isLoading {
          HStack(spacing: 6) {
            ProgressView()
              .scaleEffect(0.6)
            Text("Loading...")
              .font(.caption)
              .foregroundColor(.gray)
          }
        }
      }

      Spacer()

      // Chevron
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
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(Color.gray.opacity(0.1))
    .cornerRadius(16)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(accessibilityHint)
  }
}

// MARK: - Preview

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VStack(spacing: 12) {
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

      AccessibleInstitutionCard(
        item: ConnectedItem(
          institutionId: "ins_2",
          institutionName: "Wells Fargo",
          availableProducts: nil,
          itemId: "item_2",
          userId: "user_1",
          plaidItemId: "plaid_2",
          isActive: false,
          lastSync: nil,
          createdAt: nil,
          updatedAt: nil
        ),
        accounts: nil,
        isLoading: false
      )
    }
    .padding()
  }
}
