//
//  MonthlyPackageView.swift
//  Halo-fi-IOS
//
//  WP6 — Benefits → Monthly package. Contents checklist (SSA-795 cover ·
//  ledger · receipts n of n), an accessible preview (every page summarised
//  in text above the PDF), Send to myself / Share / Print, Mark submitted,
//  and the submission history. Delivery is share sheet, print, save, or
//  email-to-self ONLY — HaloFi never transmits anything to SSA.
//

import PDFKit
import SwiftUI
import UIKit

enum MonthKey {
    static func key(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 2026, c.month ?? 1)
    }

    static func previousMonth(from date: Date = Date()) -> String {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        return key(for: cal.date(byAdding: .month, value: -1, to: start) ?? start)
    }

    static func shifted(_ key: String, by months: Int) -> String {
        guard let d = date(for: key) else { return key }
        return Self.key(for: Calendar.current.date(byAdding: .month, value: months, to: d) ?? d)
    }

    static func date(for key: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"
        return f.date(from: key)
    }

    static func label(_ key: String) -> String {
        guard let d = date(for: key) else { return key }
        let out = DateFormatter(); out.dateFormat = "MMMM yyyy"
        return out.string(from: d)
    }

    static var current: String { key(for: Date()) }
}

struct MonthlyPackageView: View {
    let initialMonth: String?

    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(UserManager.self) private var userManager
    @Environment(DIContainer.self) private var container
    @Environment(\.openURL) private var openURL

    @State private var month: String = MonthKey.previousMonth()
    @State private var summary: SSIPacketSummary?
    @State private var submissions: [SSISubmission] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isWorking = false
    @State private var status: String?
    @State private var exportedFile: ExportedCSVFile?
    @State private var previewData: Data?
    @State private var showingChannelSheet = false
    @State private var showingMarkConfirm = false
    @State private var showingSendConfirm = false
    @State private var showingAddressPrompt = false
    @State private var address = ""
    @AccessibilityFocusState private var statusFocused: Bool

    private let ssiService: SSIServiceProtocol = SSIService.shared
    private static let channelAskedKey = "fieldOfficeChannelAsked.v1"

    init(initialMonth: String? = nil) {
        self.initialMonth = initialMonth
    }

    private var monthLabel: String { MonthKey.label(month) }
    private var accountEmail: String? { userManager.currentUser?.email }
    private var submission: SSISubmission? { summary?.submission ?? submissions.first { $0.month == month } }
    private var hasExpenses: Bool { (summary?.rowCount ?? 0) > 0 }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header
                monthSwitcher
                if isLoading {
                    ProgressView("Building the checklist…").frame(maxWidth: .infinity, minHeight: 80)
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red)
                } else if let summary {
                    checklist(summary)
                    if hasExpenses { actions }
                    markSection
                    if let status {
                        Text(status).font(.subheadline).foregroundColor(.haloTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($statusFocused)
                    }
                    fieldOfficeCard(summary.fieldOffice)
                    history
                }
                Text(ScreenReaderSummaryHeader.disclaimer)
                    .font(.caption).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                counselorButton
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Monthly package")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let initialMonth { month = initialMonth }
            await load()
        }
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: [file.url])
        }
        .sheet(isPresented: Binding(get: { previewData != nil }, set: { if !$0 { previewData = nil } })) {
            if let previewData, let summary {
                PacketPreviewSheet(data: previewData, pageSummaries: summary.pageSummaries, monthLabel: monthLabel)
            }
        }
        .sheet(isPresented: $showingChannelSheet) {
            FieldOfficeChannelSheet { channel in
                Task { await saveChannel(channel) }
            }
        }
        .alert("Mark \(monthLabel) as submitted?", isPresented: $showingMarkConfirm) {
            Button("Mark submitted") { Task { await markSubmitted() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only records that you handed the package to your field office\(summary.map { " by \($0.fieldOffice.short.lowercased())" } ?? ""). HaloFi sends nothing to Social Security.")
        }
        .alert("Email the \(monthLabel) package to yourself?", isPresented: $showingSendConfirm) {
            Button("Send") { Task { await email(to: nil) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It goes to \(accountEmail ?? "your account email") as a PDF attachment. Nothing goes to Social Security.")
        }
        .alert("Where should the package go?", isPresented: $showingAddressPrompt) {
            TextField("name@example.com", text: $address)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never)
            Button("Send") { Task { await email(to: address) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No email is on file for your account. Enter your own address.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        let count = (summary?.rowCount ?? 0) + (summary?.wageCount ?? 0)
        var detail = summary.map { s -> String in
            var text = "\(VoiceOverFormatter.count(s.rowCount, singular: "expense", plural: "expenses")) totaling \(VoiceOverFormatter.dollars(s.totalCents)). Receipts \(s.receiptCount) of \(s.rowCount)."
            if let wages = s.wageCount, wages > 0 {
                text = "\(VoiceOverFormatter.count(wages, singular: "paycheck", plural: "paychecks")) reported, gross \(VoiceOverFormatter.dollars(s.wagesGrossCents ?? 0)). " + text
            }
            return text
        } ?? "Loading."
        var tone: ScreenReaderSummaryHeader.Tone = .neutral
        if let sub = submission, sub.isSubmitted {
            detail += " Marked submitted on \(Self.spokenDate(sub.submittedAt ?? ""))."
            tone = .positive
        } else if count > 0 {
            detail += " Not marked submitted yet."
            if let due = dataManager.ssiReminders.first(where: { $0.kind == "submit_package" && $0.month == month }) {
                detail += " \(due.body)"
                tone = .watch
            }
        }
        return ScreenReaderSummaryHeader(verdict: "\(monthLabel) package", detail: detail, isEstimate: true, tone: tone)
    }

    private var monthSwitcher: some View {
        HStack(spacing: 10) {
            Button { Task { await change(by: -1) } } label: {
                Label("Earlier month", systemImage: "chevron.left").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Button { Task { await change(by: 1) } } label: {
                Label("Later month", systemImage: "chevron.right").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(month >= MonthKey.current)
        }
    }

    private func checklist(_ s: SSIPacketSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's inside").font(.headline).accessibilityAddTraits(.isHeader)
            if let wages = s.wageCount, wages > 0 {
                checkRow(ok: true, title: "Wages",
                         line: "\(VoiceOverFormatter.count(wages, singular: "paycheck", plural: "paychecks")) reported as gross wages, \(BudgetFormatter.cents(s.wagesGrossCents ?? 0)). Net deposits shown for reconciliation.")
            }
            checkRow(ok: s.rowCount > 0, title: "SSA-795 cover, pre-filled",
                     line: s.rowCount > 0 ? "\(s.expenseKind == "irwe" ? "IRWE" : s.expenseKind == "mixed" ? "BWE and IRWE" : "BWE") statement for \(s.monthLabel). Social Security number and signature left blank for you." : "No expenses logged for \(s.monthLabel) yet.")
            checkRow(ok: s.rowCount > 0, title: "Ledger",
                     line: "\(VoiceOverFormatter.count(s.rowCount, singular: "row", plural: "rows")), \(s.matchedCount) matched to bank charges.")
            checkRow(ok: s.receiptsMissing == 0 && s.rowCount > 0, title: "Receipts \(s.receiptCount) of \(s.rowCount)",
                     line: s.receiptsMissing == 0 ? "Every expense has a receipt." : "\(VoiceOverFormatter.count(s.receiptsMissing, singular: "expense is", plural: "expenses are")) missing a receipt. Add them from Work expenses before you hand this in.")
            Text("File name \(s.filename). Under 25 megabytes, no password, ready for SSA's upload tool.")
                .font(.caption).foregroundColor(.haloTextSecondary)
        }
        .padding(14)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func checkRow(ok: Bool, title: String, line: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(ok ? .haloPositive : .orange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(line).font(.subheadline).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ok ? "Ready" : "Attention"). \(title). \(line)")
    }

    private var actions: some View {
        VStack(spacing: 10) {
            actionButton("Preview pages", icon: "doc.text.magnifyingglass", hint: "Every page is described in text, then the PDF is shown.") {
                await withPacket { url in
                    previewData = try Data(contentsOf: url)
                }
            }
            actionButton("Send to myself", icon: "envelope.fill", hint: "Emails the PDF to your own address after Face ID or Touch ID.") {
                await beginSend()
            }
            actionButton("Share", icon: "square.and.arrow.up", hint: "Opens the share sheet to save to Files, AirDrop, or another app.") {
                await withPacket { url in exportedFile = ExportedCSVFile(url: url) }
            }
            actionButton("Print", icon: "printer.fill", hint: "Opens the print dialog.") {
                await withPacket { url in
                    PacketPrinter.print(data: try Data(contentsOf: url), jobName: summary?.filename ?? "HaloFi package")
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, hint: String, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack {
                if isWorking { ProgressView().padding(.trailing, 4) }
                Label(title, systemImage: icon).font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .disabled(isWorking)
        .accessibilityHint(hint)
    }

    private var markSection: some View {
        Group {
            if let sub = submission, sub.isSubmitted {
                Button { Task { await unmark() } } label: {
                    Label("Undo mark submitted", systemImage: "arrow.uturn.backward")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            } else if hasExpenses {
                Button { showingMarkConfirm = true } label: {
                    Label("Mark submitted", systemImage: "checkmark.seal.fill")
                        .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
                .accessibilityHint("Records that you handed this month's package to your field office. Stops the reminder.")
            }
        }
    }

    private func fieldOfficeCard(_ g: FieldOfficeGuidance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(g.isSet ? g.title : "How does your office like to receive these?")
                .font(.headline).accessibilityAddTraits(.isHeader)
            if g.isSet {
                ForEach(Array(g.steps.enumerated()), id: \.offset) { i, step in
                    Text("\(i + 1). \(step)").font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notes = g.notes, !notes.isEmpty {
                    Text("Your notes: \(notes)").font(.subheadline).foregroundColor(.haloTextSecondary)
                }
                Text("Change it in Settings, My field office.").font(.caption).foregroundColor(.haloTextSecondary)
            } else {
                Button { showingChannelSheet = true } label: {
                    Text("Choose how you deliver it").frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
            }
            Text(g.neverSends).font(.caption).foregroundColor(.haloTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.headline).accessibilityAddTraits(.isHeader)
            if submissions.isEmpty {
                Text("No months logged yet.").font(.subheadline).foregroundColor(.haloTextSecondary)
            }
            ForEach(submissions) { sub in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sub.monthLabel).font(.body.weight(.semibold))
                        Text(historyLine(sub)).font(.caption).foregroundColor(.haloTextSecondary)
                    }
                    Spacer()
                    Image(systemName: sub.isSubmitted ? "checkmark.seal.fill" : "clock")
                        .foregroundColor(sub.isSubmitted ? .haloPositive : .orange).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(sub.monthLabel). \(historyLine(sub))")
            }
        }
        .padding(14)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func historyLine(_ sub: SSISubmission) -> String {
        if sub.isSubmitted {
            return "Marked submitted \(Self.spokenDate(sub.submittedAt ?? ""))\(sub.channel.map { " by \(FieldOfficeChannel.title(for: $0).lowercased())" } ?? "")."
        }
        if let to = sub.emailedTo, let when = sub.emailedAt {
            return "Emailed to \(to) on \(Self.spokenDate(when)). Not marked submitted."
        }
        return "Not marked submitted."
    }

    private var counselorButton: some View {
        Button { InAppBrowser.open(ProfileExplainer.wipaURL) } label: {
            Label("Talk to a free benefits counselor", systemImage: "person.wave.2")
                .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let s = ssiService.fetchPacketSummary(month: month)
            async let subs = ssiService.fetchSubmissions()
            let (sum, list) = try await (s, subs)
            summary = sum
            submissions = list.submissions
            if !sum.fieldOffice.isSet, !UserDefaults.standard.bool(forKey: Self.channelAskedKey), sum.rowCount > 0 {
                UserDefaults.standard.set(true, forKey: Self.channelAskedKey)
                showingChannelSheet = true
            }
        } catch {
            loadError = "Couldn't load the package for \(monthLabel). \(error.localizedDescription)"
        }
    }

    private func change(by delta: Int) async {
        month = MonthKey.shifted(month, by: delta)
        status = nil
        await load()
        UIAccessibility.post(notification: .screenChanged, argument: "\(monthLabel) package.")
    }

    private func withPacket(_ body: (URL) throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await dataManager.packetToTempFile(month: month, filename: summary?.filename ?? "")
            try body(url)
        } catch {
            setStatus("Couldn't build the PDF right now. \(error.localizedDescription)", success: false)
        }
    }

    private func beginSend() async {
        do {
            try await container.biometricAuthService.authenticate(reason: "Confirm it's you before emailing your work-expense package.")
        } catch BiometricAuthService.BiometricError.cancelled {
            return
        } catch BiometricAuthService.BiometricError.notAvailable {
            // Fall through to the confirmation.
        } catch {
            setStatus("Couldn't verify it's you. Try again.", success: false)
            return
        }
        if let accountEmail, !accountEmail.isEmpty {
            showingSendConfirm = true
        } else {
            showingAddressPrompt = true
        }
    }

    private func email(to: String?) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let resp = try await dataManager.emailPacket(month: month, to: to)
            setStatus("Sent to \(resp.sentTo): \(resp.filename), \(resp.rowCount) expenses, \(resp.receiptCount) receipts.", success: true)
            await load()
        } catch {
            setStatus("Couldn't send it. \(error.localizedDescription)", success: false)
        }
    }

    private func markSubmitted() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let sub = try await dataManager.markSubmitted(month: month, channel: summary?.fieldOffice.channel, notes: nil)
            submissions.removeAll { $0.month == sub.month }
            submissions.insert(sub, at: 0)
            submissions.sort { $0.month > $1.month }
            setStatus("Marked \(monthLabel) as submitted. The reminder is off.", success: true)
            await load()
        } catch {
            setStatus("Couldn't mark it. \(error.localizedDescription)", success: false)
        }
    }

    private func unmark() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await dataManager.unmarkSubmitted(month: month)
            setStatus("\(monthLabel) is no longer marked submitted.", success: true)
            await load()
        } catch {
            setStatus("Couldn't undo it. \(error.localizedDescription)", success: false)
        }
    }

    private func saveChannel(_ channel: String) async {
        do {
            var patch = BenefitsProfilePatch()
            patch.fieldOfficeChannel = channel
            try await userManager.updateBenefitsProfile(patch)
            await userManager.refreshCapabilities()
            dataManager.markStale()
            await load()
            setStatus("Saved. Steps below now match \(FieldOfficeChannel.title(for: channel).lowercased()).", success: true)
        } catch {
            setStatus("Couldn't save that. \(error.localizedDescription)", success: false)
        }
    }

    private func setStatus(_ line: String, success: Bool) {
        status = line
        if success { Haptics.success() } else { Haptics.error() }
        UIAccessibility.post(notification: .announcement, argument: line)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { statusFocused = true }
    }

    private static func spokenDate(_ iso: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMMM d"
        return out.string(from: d)
    }
}

// MARK: - First-run channel sheet

struct FieldOfficeChannelSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("How does your office like to receive these?")
                        .font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text("Pick the one your field office told you. You can change it later in Settings, My field office.")
                        .font(.subheadline).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    FieldOfficeChannelPicker(selection: $selection)
                }
                .padding(20)
            }
            .navigationTitle("My field office")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let selection { onSave(selection) }
                        dismiss()
                    }
                    .disabled(selection == nil)
                }
            }
            .accessibilityAction(.escape) { dismiss() }
        }
    }
}

// MARK: - Accessible preview

struct PacketPreviewSheet: View {
    let data: Data
    let pageSummaries: [String]
    let monthLabel: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(VoiceOverFormatter.count(pageSummaries.count, singular: "page", plural: "pages")) in the \(monthLabel) package.")
                            .font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(Array(pageSummaries.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 32)
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 220)
                Divider()
                PDFKitView(data: data)
                    .accessibilityLabel("PDF preview of the \(monthLabel) package.")
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .accessibilityAction(.escape) { dismiss() }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil { uiView.document = PDFDocument(data: data) }
    }
}

// MARK: - Print

enum PacketPrinter {
    @MainActor
    static func print(data: Data, jobName: String) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true) { _, completed, error in
            if let error {
                UIAccessibility.post(notification: .announcement, argument: "Printing failed. \(error.localizedDescription)")
            } else if completed {
                UIAccessibility.post(notification: .announcement, argument: "Sent to the printer.")
            }
        }
    }
}
