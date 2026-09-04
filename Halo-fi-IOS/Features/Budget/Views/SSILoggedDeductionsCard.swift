//
//  SSILoggedDeductionsCard.swift
//  Halo-fi-IOS
//
//  Phase 8 — combined view of manual SSI deductions for the current
//  month. Each row shows amount, description, type, and where it
//  came from (voice vs UI entry). Swipe-to-delete removes the row
//  and triggers a budget overview refresh so projected SSI updates.
//
//  A "+ Add manually" button opens a sheet that mirrors the voice
//  flow — same fields, same defaulting rules. Voice-driven entries
//  arrive via the agent calling add_ssi_deduction, no UI needed.
//

import SwiftUI

struct SSILoggedDeductionsCard: View {
    let deductions: [SSIManualDeduction]
    let totalsCents: [String: Int]
    /// From the capabilities object: which work-expense type this user
    /// logs by default. `.bwe` only when Social Security's record
    /// confirms statutory blindness.
    let expenseType: ExpenseType
    let onAdd: () -> Void
    let onDelete: (SSIManualDeduction) async -> Void
    /// WP3 — "Needs receipt" tap / rotor "Attach receipt": opens capture.
    let onAttachReceipt: (SSIManualDeduction) -> Void
    /// WP3 — rotor "Change type".
    let onChangeType: (SSIManualDeduction, SSIExclusionType) async -> Void
    /// WP3 — rotor "View receipt".
    let onViewReceipt: (SSIManualDeduction) -> Void
    /// Phase 9 — closure that fetches the CSV bytes and returns a
    /// temp-file URL for sharing. nil disables the Share option in
    /// the export menu (used in previews/tests).
    let onExport: (() async throws -> URL)?
    /// Phase 9b — closure that emails the same CSV via the backend.
    /// The argument is the recipient address: pass nil to use the
    /// account email on file, or a non-empty string to send to a
    /// caseworker / family member / self when no account email
    /// exists yet (phone-first signup). Returns the recipient + row
    /// count for an in-card success line. nil disables the option.
    let onEmailExport: ((String?) async throws -> SSIEmailDeductionsResponse)?
    /// Pre-fill value for the email-prompt sheet. When the account
    /// has an email on file, we seed the field so the common path is
    /// "tap, glance, send". Empty/nil shows an empty field.
    let accountEmail: String?

    @State private var isExporting = false
    @State private var exportedFile: ExportedCSVFile?
    @State private var exportError: String?
    @State private var emailStatus: String?
    @State private var showingEmailPrompt = false
    @State private var isAuthenticating = false
    @State private var emailStatusClearTask: Task<Void, Never>?

    private let biometricAuth = BiometricAuthService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logged deductions")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let line = totalsLine {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if !deductions.isEmpty && (onExport != nil || onEmailExport != nil) {
                    Menu {
                        if onEmailExport != nil {
                            Button {
                                Task { await beginEmailExportFlow() }
                            } label: {
                                Label("Email the file", systemImage: "envelope.fill")
                            }
                        }
                        if let onExport {
                            Button {
                                Task { await runExport(onExport) }
                            } label: {
                                Label("Share…", systemImage: "square.and.arrow.up")
                            }
                        }
                    } label: {
                        if isExporting || isAuthenticating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .disabled(isExporting || isAuthenticating)
                    .accessibilityLabel("Export this month's SSI deductions")
                    .accessibilityHint("Opens a menu to email the CSV to a recipient you choose, or share it via the system share sheet.")
                }
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add a manual SSI deduction")
            }
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Export failed: \(exportError)")
            }
            if let emailStatus {
                Text(emailStatus)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityLabel(emailStatus)
            }

            if deductions.isEmpty {
                Text("Nothing logged this month yet. Tell Halo \"save \(expenseType == .bwe ? "fifty dollars on Uber as a BWE" : "fifty dollars on copays as IRWE")\", or tap Add.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(deductions) { entry in
                        deductionRow(entry)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .sheet(item: $exportedFile) { file in
            CSVShareSheet(url: file.url) { exportedFile = nil }
        }
        .sheet(isPresented: $showingEmailPrompt) {
            EmailRecipientPromptSheet(
                defaultEmail: accountEmail,
                onCancel: { showingEmailPrompt = false },
                onSend: { address in
                    showingEmailPrompt = false
                    if let onEmailExport {
                        Task { await runEmailExport(onEmailExport, to: address) }
                    }
                }
            )
        }
        .onDisappear {
            emailStatusClearTask?.cancel()
        }
    }

    private func runExport(_ provider: () async throws -> URL) async {
        isExporting = true
        exportError = nil
        emailStatus = nil
        defer { isExporting = false }
        do {
            exportedFile = ExportedCSVFile(url: try await provider())
        } catch {
            exportError = "Couldn't generate the file. Try again in a moment."
        }
    }

    /// Face ID / Touch ID gate before opening the recipient picker.
    /// Falls through on devices without biometrics — the recipient
    /// sheet's Send button still gates the network call.
    private func beginEmailExportFlow() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            try await biometricAuth.authenticate(
                reason: "Confirm it's you before emailing your SSI deductions."
            )
        } catch BiometricAuthService.BiometricError.cancelled {
            return
        } catch BiometricAuthService.BiometricError.notAvailable {
            // Fall through to the recipient sheet.
        } catch BiometricAuthService.BiometricError.lockedOut {
            emailStatus = "Biometric is locked. Unlock with your passcode and try again."
            scheduleEmailStatusClear()
            return
        } catch {
            emailStatus = "Couldn't verify it's you. Try again."
            scheduleEmailStatusClear()
            return
        }

        showingEmailPrompt = true
    }

    private func runEmailExport(
        _ provider: (String?) async throws -> SSIEmailDeductionsResponse,
        to address: String
    ) async {
        isExporting = true
        exportError = nil
        emailStatus = nil
        defer { isExporting = false }
        do {
            let trimmed = address.trimmingCharacters(in: .whitespaces)
            let resp = try await provider(trimmed.isEmpty ? nil : trimmed)

            let expected = trimmed.isEmpty ? (accountEmail ?? "") : trimmed
            if !expected.isEmpty,
               resp.sentTo.caseInsensitiveCompare(expected) != .orderedSame {
                emailStatus = "Sent to \(resp.sentTo) — that's not the address you entered. Contact support."
                UIAccessibility.post(
                    notification: .announcement,
                    argument: emailStatus ?? ""
                )
            } else {
                emailStatus = "Sent to \(resp.sentTo) — \(resp.rowCount) row\(resp.rowCount == 1 ? "" : "s")."
                Haptics.engine.play(.successCascade)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Sent your deductions email to \(resp.sentTo)."
                )
            }
        } catch {
            if let authErr = error as? AuthError,
               let desc = authErr.errorDescription, !desc.isEmpty {
                exportError = desc
            } else {
                exportError = "Couldn't send the email. \(error.localizedDescription)"
            }
            Logger.error("Email export failed: \(error)")
        }
        scheduleEmailStatusClear()
    }

    private func scheduleEmailStatusClear() {
        emailStatusClearTask?.cancel()
        emailStatusClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                emailStatus = nil
            }
        }
    }

    @ViewBuilder
    private func deductionRow(_ entry: SSIManualDeduction) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(typeBadge(entry.exclusionType))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeBg(entry.exclusionType), in: Capsule())
                        .foregroundStyle(badgeFg(entry.exclusionType))
                    if entry.source == "user_voice" {
                        Image(systemName: "mic.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Logged by voice")
                    }
                    if entry.linkedTransactionId != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Matched to bank transaction")
                    }
                }
                Text(entry.description)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(BudgetFormatter.cents(entry.amountCents)) on \(formattedDate(entry.occurredOn))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let value = valueLine(entry) {
                    Text(value)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if entry.resolvedMatchStatus == "needs_receipt" {
                    // Tapping the state opens capture — the receipt is the
                    // one thing SSA will ask for.
                    Button {
                        onAttachReceipt(entry)
                    } label: {
                        Label("Needs receipt — add it", systemImage: "doc.viewfinder")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.borderless)
                } else if let line = matchStatusLine(entry) {
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(matchStatusColor(entry))
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) {
                Task {
                    await onDelete(entry)
                    // Track C — haptic confirm after the network
                    // round-trip. Blind users feel "done" without
                    // waiting for the row to disappear visually.
                    Haptics.success()
                    // VoiceOver heads-up so the user knows the row
                    // was removed without having to scroll the list
                    // to confirm.
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Deleted \(entry.description) deduction."
                    )
                }
            } label: {
                Image(systemName: "trash")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(entry.description) deduction")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(entry))
        // Extra verbs live in the rotor (WP3) — one combined element per
        // row, actions reachable without hunting for tiny buttons.
        .accessibilityAction(named: entry.hasReceipt ? "Replace receipt" : "Attach receipt") {
            onAttachReceipt(entry)
        }
        .accessibilityAction(named: "View receipt") {
            if entry.hasReceipt { onViewReceipt(entry) }
        }
        .accessibilityAction(named: "Change type to \(alternateType(for: entry).rawValue.uppercased())") {
            let target = alternateType(for: entry)
            Task {
                await onChangeType(entry, target)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Changed \(entry.description) to \(fullTypeName(target))."
                )
            }
        }
        .accessibilityAction(named: "Remove") {
            Task {
                await onDelete(entry)
                Haptics.success()
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Deleted \(entry.description) deduction."
                )
            }
        }
    }

    /// WP3 — three states: Matched / Waiting for bank / Needs receipt.
    private func matchStatusLine(_ entry: SSIManualDeduction) -> String? {
        switch entry.resolvedMatchStatus {
        case "matched": return "Matched to bank transaction"
        case "waiting_for_bank":
            return isOlderThanGracePeriod(entry)
                ? "No bank charge matched yet — receipt attached"
                : "Waiting for bank to confirm"
        default: return "Needs receipt"
        }
    }

    private func matchStatusColor(_ entry: SSIManualDeduction) -> Color {
        switch entry.resolvedMatchStatus {
        case "matched": return .green
        case "waiting_for_bank": return .secondary
        default: return .orange
        }
    }

    /// "Worth up to $23.40 on your check. Estimate." — backend-computed,
    /// capped at countable earned income; always labelled.
    private func valueLine(_ entry: SSIManualDeduction) -> String? {
        guard let impact = entry.estimatedCheckImpactCents, impact > 0 else { return nil }
        return "Worth up to \(BudgetFormatter.cents(impact)) on your check. \(entry.estimateLabel ?? "Estimate")."
    }

    private func alternateType(for entry: SSIManualDeduction) -> SSIExclusionType {
        switch entry.exclusionType {
        case .bwe: return .irwe
        case .irwe: return expenseType == .bwe ? .bwe : .burial
        case .burial: return .irwe
        }
    }

    private func fullTypeName(_ type: SSIExclusionType) -> String {
        switch type {
        case .bwe: return "Blind Work Expense"
        case .irwe: return "Impairment-Related Work Expense"
        case .burial: return "Burial-fund deposit"
        }
    }

    /// 7 days is the unofficial Plaid settle SLA. After that, a
    /// missing match probably means cash / out-of-band purchase
    /// and the user should rely on their receipt for SSA proof.
    private func isOlderThanGracePeriod(_ entry: SSIManualDeduction) -> Bool {
        let prefix = String(entry.occurredOn.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: prefix) else { return false }
        return Date().timeIntervalSince(date) > 7 * 24 * 60 * 60
    }

    private var totalsLine: String? {
        let bwe = totalsCents["bwe"] ?? 0
        let irwe = totalsCents["irwe"] ?? 0
        let burial = totalsCents["burial"] ?? 0
        var parts: [String] = []
        if bwe > 0 { parts.append("BWE \(BudgetFormatter.cents(bwe))") }
        if irwe > 0 { parts.append("IRWE \(BudgetFormatter.cents(irwe))") }
        if burial > 0 { parts.append("Burial \(BudgetFormatter.cents(burial))") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ") + " this month"
    }

    private func typeBadge(_ type: SSIExclusionType) -> String {
        switch type {
        case .bwe: return "BWE"
        case .irwe: return "IRWE"
        case .burial: return "BURIAL"
        }
    }

    private func badgeBg(_ type: SSIExclusionType) -> Color {
        switch type {
        case .bwe: return .green.opacity(0.18)
        case .irwe: return .orange.opacity(0.18)
        case .burial: return .blue.opacity(0.18)
        }
    }

    private func badgeFg(_ type: SSIExclusionType) -> Color {
        switch type {
        case .bwe: return .green
        case .irwe: return .orange
        case .burial: return .blue
        }
    }

    private func formattedDate(_ iso: String) -> String {
        // Backend hands us either YYYY-MM-DD or a full ISO timestamp;
        // chop to the date prefix and parse.
        let prefix = String(iso.prefix(10))
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = inputFormatter.date(from: prefix) else { return prefix }
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM d"
        return outputFormatter.string(from: date)
    }

    private func rowAccessibilityLabel(_ entry: SSIManualDeduction) -> String {
        let typeLabel: String
        switch entry.exclusionType {
        case .bwe: typeLabel = "Blind Work Expense"
        case .irwe: typeLabel = "Impairment-Related Work Expense"
        case .burial: typeLabel = "Burial-fund deposit"
        }
        let sourceLabel = entry.source == "user_voice" ? "Logged by voice" : "Logged manually"
        var parts = [
            "\(typeLabel).",
            "\(entry.description).",
            "\(BudgetFormatter.cents(entry.amountCents)) on \(formattedDate(entry.occurredOn)).",
            "\(sourceLabel).",
        ]
        if let value = valueLine(entry) {
            parts.append(value)
        }
        if let status = matchStatusLine(entry) {
            parts.append("\(status).")
        }
        if entry.counselorQuestion == true {
            parts.append("Flagged for your counselor.")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - URL share sheet bridge

/// Wrapping URL in a private Identifiable struct avoids colliding
/// with Foundation's URL: Identifiable conformance on iOS 16+.
struct ExportedCSVFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Wraps `UIActivityViewController` so the SwiftUI `.sheet` can
/// present it for sharing the CSV. `onDismiss` clears the parent's
/// state binding and the temp file is left for the OS to clean up.
private struct CSVShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onDismiss() }
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Email recipient prompt

/// Lightweight modal for picking who receives the deductions email.
/// Presented from the "Email the file" menu item after biometric
/// auth succeeds.
///
/// Why a typed-in recipient instead of always using the account
/// email: phone-first signups don't always have an email on file,
/// and SSI users routinely need to send the file to a caseworker
/// or family member rather than themselves. Forcing it through the
/// account-email path made the feature unusable for the most common
/// flow (testing surfaced a "No email on file" 400 immediately).
private struct EmailRecipientPromptSheet: View {
    let defaultEmail: String?
    let onCancel: () -> Void
    let onSend: (String) -> Void

    @State private var address: String = ""
    @FocusState private var fieldFocused: Bool

    private var trimmed: String {
        address.trimmingCharacters(in: .whitespaces)
    }

    /// Loose client-side check so the Send button can disable for
    /// obvious typos. Real validation lives on the backend (Mailgun
    /// rejects malformed addresses anyway); this just spares users a
    /// roundtrip when they haven't finished typing.
    private var looksValid: Bool {
        let t = trimmed
        guard let at = t.firstIndex(of: "@") else { return false }
        let local = t[..<at]
        let domain = t[t.index(after: at)...]
        return !local.isEmpty && domain.contains(".") && !domain.hasSuffix(".")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("name@example.com", text: $address)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                        .accessibilityLabel("Recipient email address")
                        .accessibilityHint("Send the deductions CSV to this address.")
                } header: {
                    Text("Send to").textCase(nil)
                } footer: {
                    Text("Use your own email, your SSA caseworker's, or a family member who helps with paperwork.")
                }
            }
            .navigationTitle("Email deductions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { onSend(trimmed) }
                        .disabled(!looksValid)
                }
            }
            .onAppear {
                if address.isEmpty, let seed = defaultEmail, !seed.isEmpty {
                    address = seed
                }
                // Defer focus so the sheet's enter animation completes
                // before the keyboard slides up — avoids the jank of
                // both happening on the same frame.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    fieldFocused = true
                }
            }
        }
        .presentationDetents([.medium])
    }
}
