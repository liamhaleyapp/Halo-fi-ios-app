//
//  InstitutionDetailSheet.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 12/22/25.
//

import SwiftUI

struct InstitutionDetailSheet: View {
    let institution: ConnectedItem
    let onFixConnection: () -> Void
    let onDisconnect: () async throws -> Void

    @State private var showingDisconnectConfirmation = false
    @State private var isDisconnecting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Institution header
                VStack(spacing: 8) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text(institution.institutionName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    // Status badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(institution.isActive ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(institution.isActive ? "Connected" : "Needs Attention")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Last sync info (if available)
                    if let lastSync = institution.lastSync {
                        Text("Last synced: \(lastSync)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 24)

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                VStack(spacing: 12) {
                    // Primary action: Fix Connection (if needs attention)
                    if !institution.isActive {
                        Button {
                            onFixConnection()
                            dismiss()
                        } label: {
                            Label("Fix Connection", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                    }

                    // Disconnect button (destructive)
                    Button(role: .destructive) {
                        showingDisconnectConfirmation = true
                    } label: {
                        HStack {
                            if isDisconnecting {
                                ProgressView()
                                    .tint(.red)
                            } else {
                                Image(systemName: "link.badge.xmark")
                            }
                            Text("Disconnect Bank")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .cornerRadius(12)
                    }
                    .disabled(isDisconnecting)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Bank Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isDisconnecting)
                }
            }
            .confirmationDialog(
                "Disconnect \(institution.institutionName)?",
                isPresented: $showingDisconnectConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    performDisconnect()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove access to all accounts from this bank. You can reconnect anytime.")
            }
            .interactiveDismissDisabled(isDisconnecting)
        }
        .presentationDetents([.medium])
    }

    private func performDisconnect() {
        isDisconnecting = true
        errorMessage = nil

        Task {
            do {
                try await onDisconnect()
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to disconnect. Please try again."
                    isDisconnecting = false
                }
            }
        }
    }
}

#Preview {
    InstitutionDetailSheet(
        institution: ConnectedItem(
            institutionId: "ins_123",
            institutionName: "Chase",
            availableProducts: nil,
            itemId: "item_123",
            userId: "user_123",
            plaidItemId: "plaid_item_123",
            isActive: true,
            lastSync: "2025-12-22",
            createdAt: nil,
            updatedAt: nil
        ),
        onFixConnection: {},
        onDisconnect: {}
    )
}
