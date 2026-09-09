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
  var connectionsNeedingAttention: Int? = nil

  private var needsAttention: Bool { connectionsNeedingAttention.map { $0 > 0 } ?? !item.isActive }
  private var statusLabel: String {
    if let count = connectionsNeedingAttention, count > 0 { return "\(count) connection\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention" }
    return item.isActive ? "Connected" : "Needs attention"
  }

  // MARK: - Computed Properties

  private var accessibilityLabel: String {
    var label = item.institutionName
    label += ". " // Period for natural pause

    // Status
    label += statusLabel

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
          .foregroundColor(Color.haloTextPrimary)

        // Status indicator
        HStack(spacing: 8) {
          Circle()
            .fill(needsAttention ? Color.orange : Color.green)
            .frame(width: 8, height: 8)

          Text(statusLabel)
            .font(.caption)
            .foregroundColor(Color.haloTextSecondary)
        }

        // Account count (if available)
        if let accounts = accounts, !accounts.isEmpty {
          Text("\(accounts.count) account\(accounts.count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundColor(Color.haloTextSecondary)
        } else if isLoading {
          HStack(spacing: 6) {
            ProgressView()
              .scaleEffect(0.6)
            Text("Loading...")
              .font(.caption)
              .foregroundColor(Color.haloTextSecondary)
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
          .foregroundColor(Color.haloTextSecondary)
          .font(.caption)
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(Color.haloSecondaryBackground)
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
    Color.haloBackground.ignoresSafeArea()
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
