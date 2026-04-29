//
//  AccountsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct AccountsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(BankDataManager.self) private var bankDataManager

  // MARK: - State Variables
  @State private var showingLinkNewAccount = false
  @State private var selectedItemId: String?
  @State private var isLoadingAccounts = false
  @State private var loadError: String?
  @State private var selectedInstitution: ConnectedItem?
  
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        LinkNewAccountSection {
          showingLinkNewAccount = true
        }

        // Linked Institutions Section
        if let linkedItems = bankDataManager.linkedItems, !linkedItems.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Linked Institutions")
              .font(.headline)
              .foregroundColor(.white.opacity(0.85))

            ForEach(linkedItems, id: \.itemId) { item in
              LinkedItemCard(
                item: item,
                accounts: bankDataManager.accountsByItemId[item.itemId],
                isLoading: isLoadingAccounts && selectedItemId == item.itemId,
                bankDataManager: bankDataManager,
                onTap: {
                  selectedInstitution = item
                }
              )
              .task {
                await fetchAccountsForItem(item)
              }
            }
          }
        } else if bankDataManager.manualAccounts.isEmpty {
          // Empty state — only when there are no Plaid AND no manual accounts.
          EmptyStateView(
            icon: "building.2",
            title: "No linked accounts",
            message: "Tap \"Link New Account\" to connect your bank"
          )
        }

        // Manual Accounts Section
        if !bankDataManager.manualAccounts.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Manual Accounts")
              .font(.headline)
              .foregroundColor(.white.opacity(0.85))

            ForEach(bankDataManager.manualAccounts) { manual in
              ManualAccountRow(account: manual)
            }
          }
        }

        // Error message
        if let error = loadError {
          Text(error)
            .font(.caption)
            .foregroundColor(.red)
            .padding(.horizontal)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .padding(.bottom, 100)
    }
    .navigationTitle("Manage Linked Accounts")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      // Manual accounts aren't loaded by the main tab if the user
      // jumps straight here from Settings — refresh on first appear.
      await bankDataManager.refreshManualAccounts()
    }
    .sheet(isPresented: $showingLinkNewAccount) {
      LinkAccountChooserView()
    }
    .sheet(item: $selectedInstitution) { institution in
      InstitutionDetailSheet(
        institution: institution,
        onFixConnection: {
          // TODO: Open Plaid Link in update mode for this item
          // Requires backend to create update-mode Link token
        },
        onDisconnect: {
          try await bankDataManager.disconnectBank(itemId: institution.itemId)
        }
      )
    }
  }
  
  // MARK: - Fetch Accounts for Item
  
  private func fetchAccountsForItem(_ item: ConnectedItem) async {
    // Skip if already loading or already fetched
    guard !isLoadingAccounts else { return }

    // Check if we already have accounts for this item
    if bankDataManager.accountsByItemId[item.itemId] != nil {
      Logger.info("AccountsView: Accounts already fetched for item \(item.itemId)")
      return
    }

    selectedItemId = item.itemId
    isLoadingAccounts = true
    loadError = nil

    do {
      Logger.info("AccountsView: Fetching accounts for item \(item.itemId) (\(item.institutionName))")
      let response = try await bankDataManager.fetchAccountsForItem(itemId: item.itemId)

      await MainActor.run {
        bankDataManager.accountsByItemId[item.itemId] = response.accounts
        isLoadingAccounts = false
        selectedItemId = nil
        Logger.success("AccountsView: Fetched \(response.accounts.count) accounts for \(item.institutionName)")
      }
    } catch {
      await MainActor.run {
        isLoadingAccounts = false
        selectedItemId = nil
        loadError = "Failed to load accounts: \(error.localizedDescription)"
        Logger.error("AccountsView: Error fetching accounts: \(error)")
      }
    }
  }
}

// MARK: - Linked Item Card

struct LinkedItemCard: View {
  let item: ConnectedItem
  let accounts: [BankAccount]?
  let isLoading: Bool
  let bankDataManager: BankDataManager
  let onTap: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Institution Header
      Button(action: onTap) {
        HStack(spacing: 16) {
          Image(systemName: "building.2.fill")
            .font(.title2)
            .foregroundColor(.teal)
            .frame(width: 32, height: 32)

          VStack(alignment: .leading, spacing: 4) {
            Text(item.institutionName)
              .font(.body)
              .fontWeight(.medium)
              .foregroundColor(.white)

            HStack(spacing: 8) {
              Circle()
                .fill(item.isActive ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

              Text(item.isActive ? "Connected" : "Needs Attention")
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
            }
          }

          Spacer()

          if isLoading {
            ProgressView()
              .scaleEffect(0.8)
          } else {
            Image(systemName: "chevron.right")
              .foregroundColor(.white.opacity(0.85))
              .font(.caption)
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
      }

      // Accounts Preview (if fetched) - now tappable
      if let accounts = accounts, !accounts.isEmpty {
        VStack(spacing: 8) {
          ForEach(accounts.prefix(3), id: \.id) { account in
            NavigationLink {
              AccountDetailView(account: FinancialAccount(from: account))
                .environment(bankDataManager)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(account.name)
                    .font(.subheadline)
                    .foregroundColor(.white)

                  Text(account.type.capitalized)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                }

                Spacer()

                Text(formatCurrency(account.currentBalance ?? 0, currency: account.currency))
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .foregroundColor(.white)

                Image(systemName: "chevron.right")
                  .font(.caption2)
                  .foregroundColor(.white.opacity(0.85))
              }
              .padding(.horizontal, 20)
              .padding(.vertical, 8)
            }
            .buttonStyle(HapticPlainButtonStyle())
          }

          if accounts.count > 3 {
            HStack {
              Text("+\(accounts.count - 3) more accounts")
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
              Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
          }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
      } else if accounts?.isEmpty == true {
        // No accounts found
        HStack {
          Text("No accounts found")
            .font(.caption)
            .foregroundColor(.white.opacity(0.85))
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
      }
    }
    .background(Color.gray.opacity(0.05))
    .cornerRadius(16)
  }

  private func formatCurrency(_ amount: Double, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
  }
}

// MARK: - Manual Account Row

/// Row used in AccountsView's "Manual Accounts" section. Tapping
/// pushes ManualAccountFormView preloaded with the existing record so
/// the user can edit balance / details. Long-press → delete.
struct ManualAccountRow: View {
  let account: ManualAccount
  @Environment(BankDataManager.self) private var bankDataManager
  @State private var navigateToEdit = false
  @State private var showDeleteConfirm = false
  @State private var isDeleting = false

  var body: some View {
    NavigationLink(destination: ManualAccountFormView(existing: account)) {
      HStack(spacing: 16) {
        Image(systemName: account.accountType.systemIcon)
          .font(.title2)
          .foregroundColor(.teal)
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 4) {
          Text(account.name)
            .font(.body)
            .fontWeight(.medium)
            .foregroundColor(.white)

          HStack(spacing: 6) {
            if let inst = account.institutionName, !inst.isEmpty {
              Text(inst)
            } else {
              Text("Manual")
            }
            Text("·")
            Text(account.accountType.displayName)
          }
          .font(.caption)
          .foregroundColor(.white.opacity(0.85))
        }

        Spacer()

        Text(formatCurrency(account.balance, currency: account.currency))
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.white)

        Image(systemName: "chevron.right")
          .foregroundColor(.white.opacity(0.85))
          .font(.caption)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .background(Color.gray.opacity(0.1))
      .cornerRadius(16)
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button(role: .destructive) {
        showDeleteConfirm = true
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
    .alert("Delete this account?", isPresented: $showDeleteConfirm) {
      Button("Cancel", role: .cancel) { }
      Button("Delete", role: .destructive) {
        Task { await delete() }
      }
    } message: {
      Text("\(account.name) will be removed. This can't be undone.")
    }
  }

  @MainActor
  private func delete() async {
    isDeleting = true
    defer { isDeleting = false }
    do {
      try await ManualAccountService.shared.delete(id: account.id)
      await bankDataManager.refreshManualAccounts()
    } catch {
      Logger.warning("ManualAccountRow: delete failed — \(error)")
    }
  }

  private func formatCurrency(_ amount: Double, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
  }
}

#Preview {
  AccountsView()
    .environment(BankDataManager())
}
