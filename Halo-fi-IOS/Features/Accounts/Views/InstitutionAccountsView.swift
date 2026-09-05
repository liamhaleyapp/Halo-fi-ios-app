//
//  InstitutionAccountsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/4/25.
//

import SwiftUI

struct InstitutionAccountsView: View {
  // Scales with Dynamic Type (App Store Guideline 4).
  @ScaledMetric(relativeTo: .largeTitle) private var errorIconSize: CGFloat = 48
  @Environment(BankDataManager.self) private var bankDataManager
  let item: ConnectedItem

  @State private var accounts: [BankAccount]?
  @State private var isLoadingAccounts = false
  @State private var loadError: String?
  @State private var nicknameTarget: BankAccount?

  var body: some View {
    ZStack {
      Color.haloBackground.ignoresSafeArea()

      if isLoadingAccounts {
        loadingView
      } else if let error = loadError {
        errorView(error)
      } else if let accounts = accounts {
        if accounts.isEmpty {
          emptyAccountsView
        } else if accounts.count == 1 {
          // Single-account institution — skip the picker entirely and
          // render the detail view directly. Saves a tap when the
          // intermediary list would only have one row anyway.
          AccountDetailView(
            account: FinancialAccount(from: accounts[0], plaidItemId: item.plaidItemId),
            bankAccount: accounts[0]
          )
          .environment(bankDataManager)
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
    .sheet(item: $nicknameTarget) { account in
      AccountNicknameSheet(account: account) { updated in
        if let list = accounts { accounts = list.map { $0.idAccount == updated.idAccount ? updated : $0 } }
      }
    }
  }

  // MARK: - Accounts List View

  private func accountsListView(_ accounts: [BankAccount]) -> some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        ForEach(accounts, id: \.id) { account in
          NavigationLink {
            AccountDetailView(account: FinancialAccount(from: account, plaidItemId: item.plaidItemId), bankAccount: account)
              .environment(bankDataManager)
          } label: {
            BankAccountRow(account: account)
          }
          .buttonStyle(HapticPlainButtonStyle())
          .contextMenu {
            Button { nicknameTarget = account } label: { Label("Nickname", systemImage: "pencil") }
          }
          .accessibilityAction(named: "Add a nickname") { nicknameTarget = account }
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
        .tint(Color.haloTextPrimary)

      Text("Loading accounts...")
        .font(.body)
        .foregroundColor(Color.haloTextSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Loading accounts, please wait")
  }

  // MARK: - Error View

  private func errorView(_ error: String) -> some View {
    VStack(spacing: 20) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: errorIconSize))
        .foregroundColor(.orange)
        .accessibilityHidden(true)

      VStack(spacing: 8) {
        Text("Couldn't Load Accounts")
          .font(.title3)
          .fontWeight(.semibold)
          .foregroundColor(Color.haloTextPrimary)

        Text(error)
          .font(.body)
          .foregroundColor(Color.haloTextSecondary)
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
    // If we have cached accounts, render immediately for snappy UX,
    // then re-fetch in the background so the user sees fresh balances
    // without flicker. The previous version returned early after the
    // cached render, which is why detail views surfaced stale balances
    // until the user pulled to refresh.
    let hadCache: Bool
    if let cachedAccounts = bankDataManager.accountsByItemId[item.itemId] {
      hadCache = true
      await MainActor.run {
        self.accounts = cachedAccounts
        self.isLoadingAccounts = false
      }
    } else {
      hadCache = false
      await MainActor.run {
        isLoadingAccounts = true
        loadError = nil
      }
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
        // If we already rendered cached data, keep it visible — a
        // background-refresh failure shouldn't blow away a working view.
        if !hadCache {
          isLoadingAccounts = false
          loadError = "Failed to load accounts. Please try again."
        }
        Logger.error("InstitutionAccountsView: Error fetching accounts: \(error)")
      }
    }
  }
}

// MARK: - Bank Account Row

struct BankAccountRow: View {
  let account: BankAccount

  private var accessibilityLabel: String {
    var label = account.displayName
    if account.nickname?.isEmpty == false { label += ", \(account.name)" }

    if !account.mask.isEmpty {
      label += ", ending in \(account.mask)"
    }

    // Use appropriate wording based on account type
    if account.type.lowercased() == "credit" {
      label += ", Amount owed \(CurrencyFormatter.format(abs(account.currentBalance ?? 0), currency: account.currency))"
    } else {
      label += ", Balance \(CurrencyFormatter.format(account.currentBalance ?? 0, currency: account.currency))"
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
        Text(account.displayName)
          .font(.body)
          .fontWeight(.medium)
          .foregroundColor(Color.haloTextPrimary)
        if account.nickname?.isEmpty == false {
          Text(account.name)
            .font(.caption)
            .foregroundColor(Color.haloTextSecondary)
        }

        HStack(spacing: 4) {
          Text(account.type.capitalized)
            .font(.caption)
            .foregroundColor(Color.haloTextSecondary)

          if !account.mask.isEmpty {
            Text("•")
              .font(.caption)
              .foregroundColor(Color.haloTextSecondary)

            Text("ending in \(account.mask)")
              .font(.caption)
              .foregroundColor(Color.haloTextSecondary)
          }
        }
      }

      Spacer()

      Text(CurrencyFormatter.format(account.currentBalance ?? 0, currency: account.currency))
        .font(.body)
        .fontWeight(.medium)
        .foregroundColor((account.currentBalance ?? 0) >= 0 ? Color.haloPositive : Color.haloNegative)

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(Color.haloTextSecondary)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(Color.haloSecondaryBackground)
    .cornerRadius(16)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint("Opens this account's transactions. Actions: add a nickname.")
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

// MARK: - Nickname (2026-09-05)

/// "Call this account…": one field, Save, Clear. The nickname is shown and
/// spoken everywhere the account appears, including by Halo.
struct AccountNicknameSheet: View {
  let account: BankAccount
  var onSaved: ((BankAccount) -> Void)? = nil

  @Environment(BankDataManager.self) private var bankDataManager
  @Environment(\.dismiss) private var dismiss
  @State private var text: String = ""
  @State private var isSaving = false
  @State private var errorMessage: String?
  @AccessibilityFocusState private var focused: Bool

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 18) {
        Text("Call this account…")
          .font(.title2.weight(.bold)).foregroundColor(.haloTextPrimary)
          .accessibilityAddTraits(.isHeader)
          .accessibilityFocused($focused)
        Text("\(account.name), ending in \(account.mask). A nickname like \"HaloFi checking\" shows here, on the Money tab, and in what Halo says.")
          .font(.subheadline).foregroundColor(.haloTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
        TextField("Nickname", text: $text)
          .textFieldStyle(.roundedBorder)
          .font(.title3)
          .frame(minHeight: 44)
          .accessibilityLabel("Nickname")
          .accessibilityHint("Up to 60 characters.")
        Button { save(text) } label: {
          Text("Save").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSaving || text.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityHint("Saves the nickname and closes.")
        if account.nickname?.isEmpty == false {
          Button(role: .destructive) { save("") } label: {
            Text("Use the bank's name again").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
          }
          .buttonStyle(.bordered)
          .disabled(isSaving)
          .accessibilityHint("Removes the nickname and closes.")
        }
        if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(DesignTokens.ToneText.act) }
        Spacer()
      }
      .padding(20)
      .readableContentWidth()
      .background(Color.haloBackground.ignoresSafeArea())
      .navigationTitle("Nickname")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { CloseToolbarButton(label: "Cancel", hint: "Closes without saving.") { dismiss() } } }
      .accessibilityAction(.escape) { dismiss() }
      .onAppear {
        text = account.nickname ?? ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
      }
    }
  }

  private func save(_ value: String) {
    isSaving = true
    errorMessage = nil
    let trimmed = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
    Task {
      do {
        try await bankDataManager.setNickname(trimmed, for: account)
        var updated = account
        updated.nickname = trimmed.isEmpty ? nil : trimmed
        isSaving = false
        Haptics.success()
        onSaved?(updated)
        UIAccessibility.post(notification: .announcement, argument: trimmed.isEmpty ? "Nickname removed. Back to \(account.name)." : "Saved. This account is now \(trimmed).")
        dismiss()
      } catch {
        isSaving = false
        Haptics.error()
        errorMessage = "Couldn't save the nickname. \(error.localizedDescription)"
        UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
      }
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
