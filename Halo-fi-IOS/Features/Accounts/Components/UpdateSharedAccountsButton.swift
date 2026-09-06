//
//  UpdateSharedAccountsButton.swift
//  Halo-fi-IOS
//
//  Plaid Link in UPDATE mode against an existing connection (2026-09-05).
//  Two jobs, one button: a bank that needs a fresh sign-in ("Reconnect"),
//  and a login that stopped sharing some accounts ("Update shared
//  accounts" — Liam's Chase business checking vanished from Plaid's view
//  while the personal accounts kept working). The same item and token are
//  kept, so nothing is duplicated; the server re-syncs on success.
//

import SwiftUI
import LinkKit

struct UpdateSharedAccountsButton: View {
    let item: ConnectedItem
    /// Called after a successful update and re-sync.
    let onUpdated: () async -> Void

    @SwiftUI.Environment(PlaidManager.self) private var plaidManager
    @SwiftUI.Environment(BankDataManager.self) private var bankDataManager

    @State private var isWorking = false
    @State private var showingLink = false
    @State private var handler: Handler?
    @State private var errorMessage: String?

    private var title: String { item.isActive ? "Update shared accounts" : "Reconnect \(item.institutionName)" }

    var body: some View {
        VStack(spacing: 8) {
            Button(action: start) {
                Label(isWorking ? "Opening \(item.institutionName)…" : title,
                      systemImage: item.isActive ? "checklist" : "arrow.triangle.2.circlepath")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
            .accessibilityHint(item.isActive
                               ? "Opens \(item.institutionName) so you can add or remove the accounts it shares with HaloFi."
                               : "Opens \(item.institutionName) to sign in again.")
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fullScreenCover(isPresented: $showingLink) {
            if let handler {
                LinkController(handler: handler).ignoresSafeArea()
            }
        }
    }

    private func start() {
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let token = try await BankService.shared.getUpdateLinkToken(itemId: item.itemId)
                plaidManager.linkToken = token
                guard let created = plaidManager.createHandler(
                    onSuccess: { _ in Task { @MainActor in await finish() } },
                    onExit: { exit in
                        Task { @MainActor in
                            showingLink = false
                            isWorking = false
                            if let error = exit?.error { errorMessage = "\(item.institutionName) didn't finish: \(error.errorMessage)" }
                        }
                    }
                ) else { throw NSError(domain: "HaloFi.Plaid", code: 1, userInfo: [NSLocalizedDescriptionKey: "Link could not start."]) }
                handler = created
                showingLink = true
            } catch {
                isWorking = false
                // The server's detail can be a full Plaid error dump; log it, say one sentence.
                Logger.error("UpdateSharedAccounts: \(error)")
                errorMessage = "Couldn't open \(item.institutionName) right now. Try again in a moment."
                UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func finish() async {
        showingLink = false
        plaidManager.clearSession()
        // The server re-reads the item from Plaid (accounts + balances), then
        // the app reloads everything.
        try? await bankDataManager.syncBankData(itemId: item.itemId)
        await bankDataManager.forceRefresh()
        await onUpdated()
        isWorking = false
        UIAccessibility.post(notification: .announcement, argument: "\(item.institutionName) updated.")
    }
}
