//
//  BillConfirmSheet.swift
//  Halo-fi-IOS
//
//  "Is XYZ Property a bill?" — yes / no, one tap (2026-09-05). A yes counts
//  the stream in what is left by the 1st; a no is remembered too.
//

import SwiftUI

struct BillConfirmSheet: View {
    let streamId: String
    let merchant: String
    let amountCents: Int
    let frequencyLabel: String
    let nextExpected: String?
    var onDone: (() -> Void)? = nil

    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var focused: Bool

    init(card: AttentionCard, onDone: (() -> Void)? = nil) {
        let p = card.payload
        self.init(streamId: p.streamId ?? "", merchant: p.merchant ?? p.source ?? "this charge", amountCents: p.amountCents ?? 0,
                  frequencyLabel: p.frequencyLabel ?? "regularly", nextExpected: p.nextExpected, onDone: onDone)
    }

    init(streamId: String, merchant: String, amountCents: Int, frequencyLabel: String, nextExpected: String?, onDone: (() -> Void)? = nil) {
        self.streamId = streamId; self.merchant = merchant; self.amountCents = amountCents
        self.frequencyLabel = frequencyLabel; self.nextExpected = nextExpected; self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Is \(merchant) a bill?")
                    .font(.title2.weight(.bold)).foregroundColor(.haloTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focused)
                Text("About \(BudgetFormatter.cents(amountCents)) \(frequencyLabel)." + (nextExpected.map { " Next one expected \(TabSummaries.spokenDate($0))." } ?? ""))
                    .font(.body).foregroundColor(.haloTextSecondary)
                Text("Bills count in what is left by the 1st. Subscriptions, rent, utilities, phone, insurance, loan payments all count.")
                    .font(.subheadline).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { answer(true) } label: {
                    Label("Yes, it's a bill", systemImage: "checkmark.circle.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent).disabled(isSaving)
                Button { answer(false) } label: {
                    Label("No, not a bill", systemImage: "xmark.circle").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered).disabled(isSaving)
                if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
                Spacer()
            }
            .padding(20)
            .readableContentWidth()
            .background(Color.haloBackground.ignoresSafeArea())
            .navigationTitle("Bill?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { CloseToolbarButton(label: "Not now", hint: "Closes without answering.") { dismiss() } } }
            .accessibilityAction(.escape) { dismiss() }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true } }
        }
    }

    private func answer(_ isBill: Bool) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await dataManager.confirmBill(streamId: streamId, isBill: isBill)
                isSaving = false
                Haptics.success()
                UIAccessibility.post(notification: .announcement, argument: isBill ? "Saved. \(merchant) counts as a bill." : "Saved. \(merchant) is not a bill.")
                onDone?()
                dismiss()
            } catch {
                isSaving = false
                Haptics.error()
                errorMessage = "Couldn't save that. \(error.localizedDescription)"
                UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
            }
        }
    }
}
