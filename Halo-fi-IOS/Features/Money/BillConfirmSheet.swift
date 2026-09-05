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
    /// HaloFi's guess: "bill" or "subscription". The matching button comes first.
    var suggestedKind: String = "bill"
    var amountVaries: Bool = false
    var onDone: (() -> Void)? = nil

    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var focused: Bool

    init(card: AttentionCard, onDone: (() -> Void)? = nil) {
        let p = card.payload
        self.init(streamId: p.streamId ?? "", merchant: p.merchant ?? p.source ?? "this charge", amountCents: p.amountCents ?? 0,
                  frequencyLabel: p.frequencyLabel ?? "regularly", nextExpected: p.nextExpected,
                  suggestedKind: p.kind ?? "bill", amountVaries: p.amountVaries ?? false, onDone: onDone)
    }

    init(streamId: String, merchant: String, amountCents: Int, frequencyLabel: String, nextExpected: String?,
         suggestedKind: String = "bill", amountVaries: Bool = false, onDone: (() -> Void)? = nil) {
        self.streamId = streamId; self.merchant = merchant; self.amountCents = amountCents
        self.frequencyLabel = frequencyLabel; self.nextExpected = nextExpected
        self.suggestedKind = suggestedKind; self.amountVaries = amountVaries; self.onDone = onDone
    }

    private var suggestsSubscription: Bool { suggestedKind == "subscription" }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Is \(merchant) a \(suggestsSubscription ? "subscription" : "bill")?")
                    .font(.title2.weight(.bold)).foregroundColor(.haloTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focused)
                Text("About \(BudgetFormatter.cents(amountCents)) \(frequencyLabel)" + (amountVaries ? ", the amount varies." : ".")
                     + (nextExpected.map { " Next one expected \(TabSummaries.spokenDate($0))." } ?? ""))
                    .font(.body).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Bills are rent, utilities, phone, insurance and loan payments. Subscriptions are streaming, software and memberships. Both count in what is left by the 1st.")
                    .font(.subheadline).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if suggestsSubscription {
                    kindButton("Yes, a subscription", kind: "subscription", prominent: true)
                    kindButton("Yes, a bill", kind: "bill", prominent: false)
                } else {
                    kindButton("Yes, a bill", kind: "bill", prominent: true)
                    kindButton("Yes, a subscription", kind: "subscription", prominent: false)
                }
                Button { answer(false) } label: {
                    Label("No, neither", systemImage: "xmark.circle").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered).disabled(isSaving)
                .accessibilityHint("Saves that this is not a bill or subscription. It will not be asked again.")
                if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
                Spacer()
            }
            .padding(20)
            .readableContentWidth()
            .background(Color.haloBackground.ignoresSafeArea())
            .navigationTitle(suggestsSubscription ? "Subscription?" : "Bill?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { CloseToolbarButton(label: "Not now", hint: "Closes without answering.") { dismiss() } } }
            .accessibilityAction(.escape) { dismiss() }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true } }
        }
    }

    @ViewBuilder
    private func kindButton(_ title: String, kind: String, prominent: Bool) -> some View {
        let button = Button { answer(true, kind: kind) } label: {
            Label(title, systemImage: kind == "subscription" ? "repeat.circle.fill" : "checkmark.circle.fill")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
        }
        .disabled(isSaving)
        .accessibilityHint("Saves it as a \(kind). HaloFi remembers this payee on every account.")
        if prominent { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }

    private func answer(_ isBill: Bool, kind: String? = nil) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await dataManager.confirmBill(streamId: streamId, isBill: isBill, kind: kind)
                isSaving = false
                Haptics.success()
                UIAccessibility.post(notification: .announcement, argument: isBill ? "Saved. \(merchant) counts as a \(kind ?? "bill")." : "Saved. \(merchant) is not a bill or subscription.")
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
