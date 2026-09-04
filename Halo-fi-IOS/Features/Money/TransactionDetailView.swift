//
//  TransactionDetailView.swift
//  Halo-fi-IOS
//
//  One transaction, in full: merchant, amount, date, the account it came
//  from (institution, account name, last four), category, pending state,
//  and "Mark as work expense" for users in a benefits lane. Every row is a
//  combined VoiceOver element that reads the label before the value.
//

import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction

    @Environment(BankDataManager.self) private var bankDataManager
    @Environment(UserManager.self) private var userManager
    @Environment(\.dismiss) private var dismiss

    private var displayName: String { transaction.merchantName ?? transaction.name }
    private var amountText: String { transaction.amount.formatted(.currency(code: transaction.currency)) }
    private var isSpend: Bool { transaction.amount >= 0 }

    private var categoryName: String {
        if let pfc = transaction.personalFinanceCategory,
           let primary = pfc.additionalProperties?["primary"]?.value as? String {
            return primary.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if let categories = transaction.category, !categories.isEmpty {
            return categories.joined(separator: " • ")
        }
        return "Uncategorized"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.haloTextPrimary)
                    Text(amountText)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundColor(isSpend ? .haloNegative : .haloPositive)
                    Text(isSpend ? "Spent" : "Received")
                        .font(.caption)
                        .foregroundColor(.haloTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.haloSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("\(displayName). \(isSpend ? "Spent" : "Received") \(amountText.replacingOccurrences(of: "-", with: "")).")

                VStack(spacing: 0) {
                    detailRow("Date", DateFormatting.parseAndFormatSmart(transaction.transactionDate))
                    detailRow("Account", bankDataManager.accountLabel(for: transaction.accountId) ?? "Not linked to a known account")
                    detailRow("Category", categoryName)
                    detailRow("Status", transaction.pending ? "Pending" : "Posted")
                    if transaction.merchantName != nil, transaction.merchantName != transaction.name {
                        detailRow("Bank description", transaction.name)
                    }
                    if let channel = transaction.paymentChannel, !channel.isEmpty {
                        detailRow("Payment channel", channel.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }
                .background(Color.haloSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if userManager.capabilities.showsBenefitsLane, isSpend {
                    Button {
                        WorkExpenseHandoff.shared.offer(transaction: transaction)
                        dismiss()
                    } label: {
                        Label("Mark as work expense", systemImage: "briefcase.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Opens the work expense form on the Benefits tab with this charge filled in.")
                }
            }
            .padding(20)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline).foregroundColor(.haloTextSecondary)
                Spacer(minLength: 12)
                Text(value).font(.body).foregroundColor(.haloTextPrimary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            Divider().padding(.leading, 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
