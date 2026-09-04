//
//  ReceiptRemindersCard.swift
//  Halo-fi-IOS
//
//  WP6 — "Attach receipt for <merchant> $<amt> on <date>" rows for
//  confirmed bank charges without a receipt, plus overdue receipts on
//  logged entries (7+ days). One combined VoiceOver element per row,
//  ≥56pt targets, tap opens the receipt capture flow.
//

import SwiftUI

struct ReceiptRemindersCard: View {
    let reminders: [SSIReminder]
    let onAttach: (SSIReminder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill").foregroundStyle(.orange).accessibilityHidden(true)
                Text(VoiceOverFormatter.count(reminders.count, singular: "receipt to add", plural: "receipts to add"))
                    .font(.headline)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text("Social Security asks for proof of every work expense. A photo or the email confirmation both count.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(reminders) { reminder in
                    Button { onAttach(reminder) } label: {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.title).font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(reminder.kind == "receipt_overdue" ? "Overdue" : "Confirmed bank charge")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 10)
                        .frame(minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(reminder.title). \(reminder.kind == "receipt_overdue" ? "Overdue." : "")")
                    .accessibilityHint("Opens the camera or your photos to add the receipt.")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
