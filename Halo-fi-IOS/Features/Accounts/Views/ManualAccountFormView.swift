//
//  ManualAccountFormView.swift
//  Halo-fi-IOS
//
//  Form for adding (and later editing) a user-entered account that
//  isn't on Plaid. Reachable from LinkAccountChooserView's "Add
//  Manual Account" option, and from the row's edit action in
//  AccountsView. Saves through ManualAccountService and tells
//  BankDataManager to refresh so the lists update immediately.
//

import SwiftUI

struct ManualAccountFormView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(BankDataManager.self) private var bankDataManager

  /// When set, the form edits this account. When nil, it creates one.
  var existing: ManualAccount?

  @State private var name: String = ""
  @State private var institutionName: String = ""
  @State private var accountType: ManualAccountType = .checking
  @State private var balanceText: String = ""
  @State private var currency: String = "USD"
  @State private var notes: String = ""

  @State private var isSaving = false
  @State private var errorMessage: String?

  private var isEditing: Bool { existing != nil }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty
      && Double(balanceText.replacingOccurrences(of: ",", with: "")) != nil
      && !isSaving
  }

  var body: some View {
    Form {
      Section("Account") {
        TextField("Name", text: $name)
          .textInputAutocapitalization(.words)
        TextField("Institution (optional)", text: $institutionName)
          .textInputAutocapitalization(.words)
        Picker("Type", selection: $accountType) {
          ForEach(ManualAccountType.allCases) { t in
            Label(t.displayName, systemImage: t.systemIcon).tag(t)
          }
        }
      }

      Section("Balance") {
        TextField("Balance", text: $balanceText)
          .keyboardType(.decimalPad)
        TextField("Currency", text: $currency)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
      }

      Section("Notes") {
        TextField("Optional notes", text: $notes, axis: .vertical)
          .lineLimit(3...6)
      }

      if let errorMessage {
        Section {
          Text(errorMessage)
            .foregroundColor(.red)
            .font(.callout)
        }
      }
    }
    .navigationTitle(isEditing ? "Edit Manual Account" : "New Manual Account")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(isSaving ? "Saving…" : "Save") {
          Task { await save() }
        }
        .disabled(!canSave)
      }
    }
    .onAppear { populateFromExisting() }
  }

  // MARK: - Actions

  private func populateFromExisting() {
    guard let existing else { return }
    name = existing.name
    institutionName = existing.institutionName ?? ""
    accountType = existing.accountType
    balanceText = String(existing.balance)
    currency = existing.currency
    notes = existing.notes ?? ""
  }

  @MainActor
  private func save() async {
    guard let balance = Double(balanceText.replacingOccurrences(of: ",", with: "")) else {
      errorMessage = "Enter a valid balance amount."
      return
    }

    isSaving = true
    errorMessage = nil
    defer { isSaving = false }

    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    let trimmedInst = institutionName.trimmingCharacters(in: .whitespaces)
    let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
    let normalizedCurrency = currency.uppercased().trimmingCharacters(in: .whitespaces)

    do {
      if let existing {
        let payload = ManualAccountUpdateRequest(
          name: trimmedName,
          institutionName: trimmedInst.isEmpty ? nil : trimmedInst,
          accountType: accountType,
          balance: balance,
          currency: normalizedCurrency.isEmpty ? "USD" : normalizedCurrency,
          notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        _ = try await ManualAccountService.shared.update(id: existing.id, payload: payload)
      } else {
        let payload = ManualAccountCreateRequest(
          name: trimmedName,
          institutionName: trimmedInst.isEmpty ? nil : trimmedInst,
          accountType: accountType,
          balance: balance,
          currency: normalizedCurrency.isEmpty ? "USD" : normalizedCurrency,
          notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
        _ = try await ManualAccountService.shared.create(payload)
      }
      await bankDataManager.refreshManualAccounts()
      dismiss()
    } catch {
      Logger.error("ManualAccountFormView: save failed — \(error)")
      errorMessage = "Couldn't save. \(error.localizedDescription)"
    }
  }
}

#Preview {
  NavigationStack {
    ManualAccountFormView()
      .environment(BankDataManager())
  }
}
