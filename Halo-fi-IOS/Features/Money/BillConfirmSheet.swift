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
    private var reminderCard: AttentionCard? = nil

    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    @State private var cancellationDate = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var loadedStream: RecurringStream?
    @State private var isLoading = true
    /// "Name this payment" (2026-09-29): saved on its own for a confirmed
    /// stream, otherwise carried as the label of the next Yes answer.
    @State private var paymentName = ""
    @AccessibilityFocusState private var focused: Bool

    init(card: AttentionCard, onDone: (() -> Void)? = nil) {
        let p = card.payload
        self.init(streamId: p.streamId ?? "", merchant: p.merchant ?? p.source ?? "this charge", amountCents: p.amountCents ?? p.toCents ?? 0,
                  frequencyLabel: p.frequencyLabel ?? "regularly", nextExpected: p.nextExpected,
                  suggestedKind: p.kind ?? "bill", amountVaries: p.amountVaries ?? false, onDone: onDone)
        self.reminderCard = card
    }

    init(streamId: String, merchant: String, amountCents: Int, frequencyLabel: String, nextExpected: String?,
         suggestedKind: String = "bill", amountVaries: Bool = false, onDone: (() -> Void)? = nil) {
        self.streamId = streamId; self.merchant = merchant; self.amountCents = amountCents
        self.frequencyLabel = frequencyLabel; self.nextExpected = nextExpected
        self.suggestedKind = suggestedKind; self.amountVaries = amountVaries; self.onDone = onDone
    }

    private var stream: RecurringStream? { loadedStream ?? dataManager.bills?.streams.first { $0.streamId == streamId } }
    private var isTracked: Bool { stream?.userConfirmed == true || stream?.cancelledOn != nil }

    private var suggestsSubscription: Bool { (stream?.kind ?? suggestedKind) == "subscription" }
    /// Opened from an attention card and still without a yes or no.
    private var canDefer: Bool { reminderCard != nil && stream?.userConfirmed == nil }
    private var trimmedName: String { paymentName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(isTracked ? merchant : "Is \(merchant) a \(suggestsSubscription ? "subscription" : "bill")?")
                    .font(.title2.weight(.bold)).foregroundColor(.haloTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focused)
                Text("About \(BudgetFormatter.cents(stream?.displayCents ?? amountCents)) \(stream?.frequencyLabel ?? frequencyLabel).")
                    .font(.body).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let evidence = stream?.evidenceLine {
                    Text(evidence).font(.subheadline).foregroundColor(.haloTextSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if let changed = stream?.amountChangedLine {
                    Text(changed).font(.body).foregroundColor(.haloTextSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if let extra = stream?.extraPaymentsLine {
                    Text(extra).font(.subheadline).foregroundColor(.haloTextSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if let card = reminderCard, card.id.hasPrefix("cancelled-charge:") {
                    Text(card.line).font(.body).foregroundColor(DesignTokens.ToneText.watch)
                }
                if let stream {
                    Text(stream.forecastLine).font(.body)
                    if stream.cancelledOn == nil {
                        DatePicker("Cancellation effective date", selection: $cancellationDate, displayedComponents: .date)
                            .disabled(isSaving || isLoading)
                        Button { recordCancellation(stream, undo: false) } label: {
                            Label("I cancelled this", systemImage: "calendar.badge.minus")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                        }
                            .buttonStyle(.bordered).disabled(isSaving || isLoading)
                            .accessibilityHint("Records your cancellation and stops future forecasts. Does not cancel with the company.")
                    } else if let cancelledOn = stream.cancelledOn {
                        Text("Cancelled effective \(TabSummaries.spokenDate(cancelledOn)).")
                            .font(.subheadline).foregroundColor(.haloTextSecondary)
                        Button("Undo cancellation") { recordCancellation(stream, undo: true) }
                            .frame(minHeight: 48).disabled(isSaving || isLoading)
                    }
                    Text("HaloFi records your cancellation; it does not cancel with the company. We'll flag another posted charge for review. Missing bank data cannot confirm that billing stopped.")
                        .font(.subheadline).foregroundColor(.haloTextSecondary)
                }
                if stream?.assumedByHalo == true {
                    Text("HaloFi assumed this is a \(stream?.kindWord ?? "bill"). Change it below if that's wrong.")
                        .font(.body).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isTracked {
                    DisclosureGroup("Change classification") {
                        classificationButtons
                        nameField
                    }
                } else {
                    classificationButtons
                    if canDefer {
                        Button { deferQuestion() } label: {
                            Label("Not sure yet", systemImage: "questionmark.circle")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.bordered).disabled(isSaving)
                        .accessibilityHint("Leaves this unanswered. HaloFi asks again in a month.")
                    }
                    DisclosureGroup("Name this payment") { nameField }
                }
                AttentionDetailReminder(card: reminderCard).disabled(isSaving)
                if isLoading { ProgressView("Loading payment details…") }
                if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(.red)
                    if loadedStream == nil { Button("Try again") { Task { await loadDetails() } }.frame(minHeight: 44) }
                }
                Spacer()
            }
            .padding(20)
            .readableContentWidth()
            }
            .background(Color.haloBackground.ignoresSafeArea())
            .navigationTitle(suggestsSubscription ? "Subscription" : "Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { CloseToolbarButton { dismiss() } } }
            .accessibilityAction(.escape) { dismiss() }
            .onAppear { Diagnostics.screen("bill_sheet"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true } }
            .task { await loadDetails() }
        }
    }

    /// "Yes" agrees with HaloFi's guess; "No, a …" corrects it.
    @ViewBuilder
    private var classificationButtons: some View {
        if suggestsSubscription {
            kindButton("Yes, a subscription", kind: "subscription", prominent: true)
            kindButton("No, a bill", kind: "bill", prominent: false)
        } else {
            kindButton("Yes, a bill", kind: "bill", prominent: true)
            kindButton("No, a subscription", kind: "subscription", prominent: false)
        }
        Button { answer(false) } label: {
            Label("No, neither", systemImage: "xmark.circle").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered).disabled(isSaving)
        .accessibilityHint("Saves that this is not a bill or subscription. Also for something you cancelled or a one-time payment.")
        Text("Also for something you cancelled or a one-time payment.")
            .font(.subheadline).foregroundColor(.haloTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    /// A name in the user's words ("Rent") for a payee the bank names badly.
    /// Confirmed streams save at once; unanswered ones save with the Yes.
    @ViewBuilder
    private var nameField: some View {
        TextField("Rent, phone, car insurance…", text: $paymentName)
            .textFieldStyle(CustomTextFieldStyle())
            .submitLabel(.done)
            .disabled(isSaving)
            .accessibilityLabel("Name this payment")
        if isTracked {
            Button { saveName() } label: {
                Label("Save name", systemImage: "tag")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.bordered).disabled(isSaving || isLoading || trimmedName.isEmpty)
            .accessibilityHint("Renames this payment everywhere in HaloFi.")
        } else {
            Text("Saved with your answer above.")
                .font(.subheadline).foregroundColor(.haloTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadDetails() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await RecurringService.shared.bills()
            guard !Task.isCancelled else { return }
            loadedStream = response.streams.first { $0.streamId == streamId }
            errorMessage = loadedStream == nil ? "This payment is no longer available. Close and refresh Calendar." : nil
        } catch {
            errorMessage = "Couldn't load payment details. \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func kindButton(_ title: String, kind: String, prominent: Bool) -> some View {
        let button = Button { answer(true, kind: kind) } label: {
            Label(title, systemImage: kind == "subscription" ? "repeat.circle.fill" : "checkmark.circle.fill")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 56)
        }
        .disabled(isSaving)
        .accessibilityHint((title.hasPrefix("Yes") ? "Confirms it as a \(kind)." : "Corrects it to a \(kind).") + " HaloFi remembers this payee on every account.")
        if prominent { button.buttonStyle(.borderedProminent) } else { button.buttonStyle(.bordered) }
    }

    private func recordCancellation(_ stream: RecurringStream, undo: Bool) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
                f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
                _ = try await RecurringService.shared.setCancellation(stream: stream, date: undo ? nil : f.string(from: cancellationDate))
                dataManager.invalidateCalendar()
                dataManager.invalidateAttention()
                await dataManager.refresh()
                UIAccessibility.post(notification: .announcement, argument: undo ? "Cancellation undone." : "Cancellation recorded.")
                onDone?(); dismiss()
            } catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }

    /// "Not sure yet": the card rests for a month; the stream keeps no answer.
    private func deferQuestion() {
        guard let card = reminderCard else { return }
        isSaving = true
        errorMessage = nil
        Task {
            let saved = await dataManager.dismissCard(card, days: 30)
            isSaving = false
            guard saved else {
                Haptics.error()
                errorMessage = "Couldn't save that. Try again."
                UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
                return
            }
            UIAccessibility.post(notification: .announcement, argument: "Okay. I'll ask again in a month.")
            onDone?()
            dismiss()
        }
    }

    private func saveName() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await dataManager.confirmBill(streamId: streamId, isBill: true, label: name, kind: stream?.kind)
                await loadDetails()
                isSaving = false
                Haptics.success()
                UIAccessibility.post(notification: .announcement, argument: "Saved. This payment is now called \(name).")
            } catch {
                isSaving = false
                Haptics.error()
                errorMessage = "Couldn't save that name. \(error.localizedDescription)"
                UIAccessibility.post(notification: .announcement, argument: errorMessage ?? "")
            }
        }
    }

    private func answer(_ isBill: Bool, kind: String? = nil) {
        isSaving = true
        errorMessage = nil
        // A name typed before the Yes rides along with it; a No never renames.
        let label = isBill && !trimmedName.isEmpty ? trimmedName : nil
        Task {
            do {
                try await dataManager.confirmBill(streamId: streamId, isBill: isBill, label: label, kind: kind)
                isSaving = false
                Haptics.success()
                UIAccessibility.post(notification: .announcement, argument: isBill ? "Saved. \(label ?? merchant) counts as a \(kind ?? "bill")." : "Saved. \(merchant) is not a bill or subscription.")
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
