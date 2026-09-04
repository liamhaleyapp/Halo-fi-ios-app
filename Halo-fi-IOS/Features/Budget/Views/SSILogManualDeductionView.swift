//
//  SSILogManualDeductionView.swift
//  Halo-fi-IOS
//
//  Log a work expense by hand (the voice path goes through the agent's
//  add_ssi_deduction tool). WP3 adds the receipt: take a photo / choose from
//  library / choose a file; on-device OCR prefills amount, description and
//  date and says "Found 23 dollars and 40 cents at Uber on September 3.
//  Confirm or edit." with focus moved to that summary. Low-confidence reads
//  fall back to the server-side extraction. Nothing is saved until Save.
//
//  Type defaulting comes from the capabilities object: BWE only when Social
//  Security's record confirms statutory blindness, IRWE otherwise. When
//  `bweLocked`, the BWE choice is visible but disabled and the footer
//  explains the BPQY unlock path (hard rule 4).
//

import SwiftUI

/// Everything the form hands back on Save.
struct ManualDeductionDraft: Equatable {
    var type: SSIExclusionType
    var amountCents: Int
    var description: String
    var occurredOn: Date
    var notes: String?
    var receipt: ManualDeductionReceiptFields
}

struct SSILogManualDeductionView: View {
    let capabilities: UserCapabilities
    /// A receipt that arrived before the form opened (share extension, or
    /// "Attach receipt" on a row that opened the capture first).
    let initialReceipt: CapturedReceipt?
    /// "Mark as work expense" from a transaction: amount, description and
    /// date arrive prefilled; the user confirms or edits.
    let initialDraft: WorkExpenseDraft?
    let onSave: (ManualDeductionDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String = ""
    @State private var description: String = ""
    @State private var selectedType: SSIExclusionType
    @State private var occurredOn: Date = Date()
    @State private var notes: String = ""
    @State private var counselorQuestion = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var descriptionError: String?

    // Receipt state
    @State private var showingCapture = false
    @State private var receipt: CapturedReceipt?
    @State private var receiptAssetId: String?
    @State private var isProcessingReceipt = false
    @State private var receiptStatus: String?
    @State private var ocrSummary: String?
    @State private var extracted = ManualDeductionReceiptFields()

    private enum Focus: Hashable { case summary, description, error }
    @AccessibilityFocusState private var focus: Focus?

    private let receiptService: ReceiptServiceProtocol = ReceiptService.shared

    init(
        capabilities: UserCapabilities,
        initialReceipt: CapturedReceipt? = nil,
        initialDraft: WorkExpenseDraft? = nil,
        onSave: @escaping (ManualDeductionDraft) async throws -> Void
    ) {
        self.capabilities = capabilities
        self.initialReceipt = initialReceipt
        self.initialDraft = initialDraft
        self.onSave = onSave
        _selectedType = State(initialValue: capabilities.expenseType == .bwe ? .bwe : .irwe)
        if let draft = initialDraft {
            _amountText = State(initialValue: String(format: "%.2f", Double(draft.amountCents) / 100.0))
            _description = State(initialValue: draft.description)
            _occurredOn = State(initialValue: min(draft.occurredOn, Date()))
        }
    }

    private var bweLocked: Bool { capabilities.bweLocked }

    var body: some View {
        NavigationStack {
            Form {
                receiptSection

                Section {
                    if let ocrSummary {
                        Text(ocrSummary)
                            .font(.callout.weight(.semibold))
                            .accessibilityAddTraits(.isStaticText)
                            .accessibilityFocused($focus, equals: .summary)
                    }
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Amount in dollars")
                    TextField("Description (e.g. Uber to work)", text: $description)
                        .accessibilityLabel("Description of the expense. Required.")
                        .accessibilityFocused($focus, equals: .description)
                        .onChange(of: description) { _, _ in descriptionError = nil }
                    if let descriptionError {
                        Text(descriptionError)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .accessibilityFocused($focus, equals: .error)
                    }
                } header: {
                    Text("Expense").textCase(nil)
                }

                Section {
                    Picker("Type", selection: $selectedType) {
                        ForEach(SSIExclusionType.allCases, id: \.self) { type in
                            Text(label(for: type)).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint(typeHint)
                    .onChange(of: selectedType) { _, newValue in
                        if newValue == .bwe && bweLocked {
                            selectedType = .irwe
                            UIAccessibility.post(
                                notification: .announcement,
                                argument: "Blind Work Expenses are locked until Social Security's record confirms statutory blindness. Logged as an Impairment-Related Work Expense instead."
                            )
                        }
                    }
                    Text(valueLine)
                        .font(.callout)
                        .foregroundColor(.haloTextSecondary)
                        .accessibilityLabel(valueLine)
                } header: {
                    Text("Type").textCase(nil)
                } footer: {
                    Text(bweLocked
                         ? "Blind Work Expenses — locked until Social Security's record confirms statutory blindness. Check your award letter or BPQY, then update Settings, Benefits profile. Until then this is logged as IRWE."
                         : typeFooter)
                }

                Section {
                    DatePicker(
                        "Date of expense",
                        selection: $occurredOn,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                } header: {
                    Text("When").textCase(nil)
                } footer: {
                    Text("Cannot be more than 90 days ago. SSA reporting is monthly.")
                }

                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: false)
                    Toggle(isOn: $counselorQuestion) {
                        Text("Not sure this counts? Ask my counselor")
                    }
                    .accessibilityHint("Adds this expense to the question list under Settings, Questions for my counselor.")
                } header: {
                    Text("Notes").textCase(nil)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .accessibilityFocused($focus, equals: .error)
                    }
                }
            }
            .navigationTitle("Log work expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Saving…" : "Save") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || isProcessingReceipt || parsedAmountCents == nil)
                }
            }
            .sheet(isPresented: $showingCapture) {
                ReceiptCaptureView { captured in
                    handle(captured)
                }
            }
            .onAppear {
                if let initialReceipt, receipt == nil {
                    handle(initialReceipt)
                }
            }
            .accessibilityAction(.escape) { dismiss() }
        }
    }

    // MARK: - Receipt section

    @ViewBuilder
    private var receiptSection: some View {
        Section {
            if receipt == nil {
                Button {
                    showingCapture = true
                } label: {
                    Label("Add receipt", systemImage: "doc.viewfinder")
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Take a photo, choose one from your library, or pick a file. Halo reads the amount, date and vendor for you.")
            } else {
                HStack {
                    Image(systemName: receiptAssetId == nil ? "doc.badge.clock" : "checkmark.seal.fill")
                        .foregroundStyle(receiptAssetId == nil ? .orange : .green)
                        .accessibilityHidden(true)
                    Text(receiptStatus ?? "Receipt attached")
                    Spacer()
                    Button("Replace") { showingCapture = true }
                        .accessibilityLabel("Replace receipt")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(receiptStatus ?? "Receipt attached")
                if isProcessingReceipt {
                    ProgressView("Reading the receipt…")
                        .accessibilityLabel("Reading the receipt")
                }
            }
        } header: {
            Text("Receipt").textCase(nil)
        } footer: {
            Text(receipt == nil
                 ? "A receipt is the proof Social Security asks for. You can add it now or later; cash expenses without a receipt still count."
                 : "Stored privately in your account. Check the amount, date and description before saving.")
        }
    }

    // MARK: - Receipt handling

    private func handle(_ captured: CapturedReceipt) {
        receipt = captured
        receiptAssetId = nil
        receiptStatus = "Receipt added — reading it now"
        isProcessingReceipt = true
        Task { await processReceipt(captured) }
    }

    private func processReceipt(_ captured: CapturedReceipt) async {
        defer { isProcessingReceipt = false }

        // 1. On-device OCR (primary).
        var parse = ReceiptParse.empty
        if let image = imageForOCR(captured) {
            if let lines = try? await ReceiptTextRecognizer.recognizeLines(in: image) {
                parse = ReceiptOCRParser.parse(lines: lines)
            }
        }

        // 2. Upload (needed for save either way, and for the fallback).
        do {
            let uploaded = try await receiptService.upload(captured)
            receiptAssetId = uploaded.assetId
            receiptStatus = "Receipt attached"
        } catch {
            receiptStatus = "Receipt saved on this phone only — upload failed. You can still save and add it later."
            UIAccessibility.post(notification: .announcement, argument: receiptStatus ?? "")
        }

        // 3. Server fallback when the on-device read is weak.
        if parse.needsFallback, let assetId = receiptAssetId {
            if let server = try? await receiptService.extract(assetId: assetId) {
                if parse.amountCents == nil, let cents = server.amountCents { parse.amountCents = cents }
                if parse.merchant == nil, let vendor = server.vendor { parse.merchant = vendor }
                if parse.date == nil, let d = server.date, let date = Self.isoFormatter.date(from: d) { parse.date = date }
                parse.confidence = max(parse.confidence, server.confidence)
            }
        }

        applyPrefill(parse)
    }

    private func imageForOCR(_ captured: CapturedReceipt) -> UIImage? {
        if captured.contentType == "application/pdf" {
            return ReceiptTextRecognizer.firstPageImage(pdfData: captured.data)
        }
        return UIImage(data: captured.data)
    }

    private func applyPrefill(_ parse: ReceiptParse) {
        extracted.assetId = receiptAssetId
        extracted.vendor = parse.merchant
        extracted.extractedAmountCents = parse.amountCents
        extracted.extractedDate = parse.date.map { Self.isoFormatter.string(from: $0) }
        extracted.extractionConfidence = parse.confidence

        if let cents = parse.amountCents, amountText.isEmpty {
            amountText = String(format: "%.2f", Double(cents) / 100.0)
        }
        if let merchant = parse.merchant, description.isEmpty {
            description = merchant
        }
        if let date = parse.date { occurredOn = date }

        var parts: [String] = []
        if let cents = parse.amountCents { parts.append("Found \(VoiceOverFormatter.dollarsAndCents(cents))") }
        if let merchant = parse.merchant { parts.append(parts.isEmpty ? "Found \(merchant)" : "at \(merchant)") }
        if let date = parse.date { parts.append("on \(Self.spokenDateFormatter.string(from: date))") }
        let summary: String
        if parts.isEmpty {
            summary = "Couldn't read the receipt. Enter the amount and description, and keep the photo attached."
        } else {
            summary = parts.joined(separator: " ") + ". Confirm or edit."
        }
        ocrSummary = summary
        Haptics.engine.play(.tapLight)
        UIAccessibility.post(notification: .announcement, argument: summary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = .summary }
    }

    // MARK: - Derived

    private var parsedAmountCents: Int? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard let dollars = Double(trimmed), dollars > 0 else { return nil }
        return Int((dollars * 100).rounded())
    }

    /// Local, uncapped preview; the backend caps at countable earned income.
    private var valueLine: String {
        guard let cents = parsedAmountCents else { return "Worth up to — on your SSI check. Estimate." }
        let impact: Int
        switch selectedType {
        case .bwe: impact = bweLocked ? 0 : cents
        case .irwe: impact = cents / 2
        case .burial: impact = 0
        }
        if impact == 0 { return "This doesn't change your SSI check this month. Estimate." }
        return "Worth up to \(VoiceOverFormatter.dollarsAndCents(impact)) on your SSI check. Estimate."
    }

    private func label(for type: SSIExclusionType) -> String {
        switch type {
        case .bwe: return "BWE"
        case .irwe: return "IRWE"
        case .burial: return "Burial"
        }
    }

    private var typeFooter: String {
        switch selectedType {
        case .bwe:
            return "Blind Work Expense — $1 of SSI preserved per $1 spent. Statutorily blind users only. Estimate."
        case .irwe:
            return "Impairment-Related Work Expense — about $0.50 of SSI preserved per $1 spent. Estimate."
        case .burial:
            return "Designated burial-fund deposit — excluded from countable resources up to $1,500."
        }
    }

    private var typeHint: String {
        if capabilities.expenseType == .bwe {
            return "Default for statutorily blind users is BWE (worth twice as much per dollar as IRWE). Switch to IRWE for medical expenses unrelated to enabling work."
        }
        if bweLocked {
            return "BWE is locked until Social Security confirms statutory blindness. Default is IRWE. Burial covers designated burial-fund deposits."
        }
        return "Default is IRWE. Burial covers designated burial-fund deposits."
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let spokenDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    // MARK: - Submit

    private func submit() async {
        guard let cents = parsedAmountCents else { return }
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        guard !trimmedDesc.isEmpty else {
            descriptionError = "A description is required — say what the expense was, like \"Uber to work\"."
            Haptics.error()
            UIAccessibility.post(notification: .announcement, argument: descriptionError ?? "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .error }
            return
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        var receiptFields = extracted
        receiptFields.assetId = receiptAssetId
        receiptFields.pending = receiptAssetId == nil
        receiptFields.counselorQuestion = counselorQuestion

        let draft = ManualDeductionDraft(
            type: selectedType,
            amountCents: cents,
            description: trimmedDesc,
            occurredOn: occurredOn,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            receipt: receiptFields
        )

        isSubmitting = true
        errorMessage = nil
        do {
            try await onSave(draft)
            Haptics.success()
            let saved = receiptAssetId == nil
                ? "Logged. Add the receipt when you can; Halo will remind you."
                : "Logged with receipt."
            UIAccessibility.post(notification: .announcement, argument: saved)
            isSubmitting = false
            dismiss()
        } catch {
            Haptics.error()
            UIAccessibility.post(
                notification: .announcement,
                argument: "Couldn't save the expense. \(error.localizedDescription)"
            )
            isSubmitting = false
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = .error }
        }
    }
}
