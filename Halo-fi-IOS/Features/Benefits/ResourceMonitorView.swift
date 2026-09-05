//
//  ResourceMonitorView.swift
//  Halo-fi-IOS
//
//  The SSI resource monitor screen (WP4), grown from BudgetView's old
//  ssiSection. Per-account counted list, excluded list with reasons,
//  alerts, and the Watch/Act actions: Move to ABLE · Spending that counts ·
//  Ask my counselor. Every number is an estimate and says so.
//

import SwiftUI

struct ResourceMonitorView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(BankDataManager.self) private var bankDataManager
    @Environment(UserManager.self) private var userManager
    @Environment(\.openURL) private var openURL

    @State private var explainer: MonitorAction?

    enum MonitorAction: String, Identifiable {
        case moveToABLE, spendingThatCounts
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let ssi = dataManager.overview?.ssiStatus {
                    header(ssi)
                    if let resources = ssi.resources {
                        SSIResourceHeroCard(resources: resources)
                        if let iso = resources.measurementDateIso, let days = resources.daysUntilMeasurement {
                            measurementRow(iso: iso, days: days, escalated: resources.escalated == true)
                        }
                        if resources.effectiveStatus != "ok" {
                            actions(resources)
                        }
                    }
                    if let alerts = dataManager.overview?.ssiAlerts, !alerts.isEmpty {
                        ForEach(alerts) { entry in SSIAlertBanner(entry: entry) }
                    }
                    if let income = ssi.income, income.paymentSuspendedOverResources == true {
                        SSISpendDownBanner(spendDownFormatted: income.spendDownFormatted)
                    }
                    countedAccounts
                    excludedList(ssi)
                    if let income = ssi.income, income.paymentSuspendedOverResources != true {
                        SSIIncomeHeroCard(income: income)
                    }
                    if let next = ssi.nextSsaDeposit {
                        SSINextDepositCard(next: next)
                    }
                    Text(ScreenReaderSummaryHeader.disclaimer)
                        .font(.caption)
                        .foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    counselorButton
                } else {
                    ProgressView("Loading…")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 100)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Resource monitor")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await dataManager.refresh() }
        .sheet(item: $explainer) { action in
            MonitorActionSheet(action: action, resources: dataManager.overview?.ssiStatus.resources)
        }
    }

    // MARK: - Header

    private func header(_ ssi: SSIStatus) -> some View {
        let res = ssi.resources
        let (word, tone) = res.map(TabSummaries.resourceVerdict) ?? ("Resources", .neutral)
        var detail = ""
        if let res {
            detail = "\(VoiceOverFormatter.dollars(res.currentCents)) of \(VoiceOverFormatter.dollars(res.limitCents)) counted."
            if res.effectiveStatus == "over" {
                detail += " This could put you over the limit Social Security checks on the 1st."
            } else if let move = res.spendOrMoveCents, move > 0 {
                detail += " About \(VoiceOverFormatter.dollars(move)) would need to go to needs or into an ABLE account to be safely under."
            }
        }
        return ScreenReaderSummaryHeader(verdict: word, detail: detail, isEstimate: true, tone: tone)
    }

    private func measurementRow(iso: String, days: Int, escalated: Bool) -> some View {
        let date = spokenDate(iso)
        let text = "SSA measures on \(date), \(days == 1 ? "tomorrow" : "in \(days) days")."
            + (escalated ? " Watch reads as Act this close to the 1st." : "")
        return HStack(spacing: 10) {
            Image(systemName: "calendar").foregroundColor(.blue).accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundColor(.haloTextPrimary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions (Watch / Act)

    private func actions(_ resources: SSIResources) -> some View {
        VStack(spacing: 10) {
            if userManager.benefitsProfile.hasAbleAccount == true {
                actionButton("Move to ABLE", icon: "arrow.down.to.line.circle") { explainer = .moveToABLE }
            }
            actionButton("Spending that counts", icon: "cart") { explainer = .spendingThatCounts }
            actionButton("Ask my counselor", icon: "person.wave.2") { InAppBrowser.open(ProfileExplainer.wipaURL) }
        }
        .padding(.top, 4)
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Counted / excluded

    private var countedAccounts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Counted").font(.headline).foregroundColor(.haloTextSecondary).accessibilityAddTraits(.isHeader)
            let accounts = bankDataManager.accountsByItemId.values.flatMap { $0 }.filter { $0.isActive }
            if accounts.isEmpty && bankDataManager.manualAccounts.isEmpty {
                Text("No accounts linked yet.").font(.subheadline).foregroundColor(.haloTextSecondary)
            }
            ForEach(accounts) { account in
                let counted = SSIAccountRule.counted(type: account.type)
                accountLine(
                    name: account.name,
                    cents: Int(((account.currentBalance ?? 0) * 100).rounded()),
                    status: counted ? "counted" : "not a resource — it's what you owe"
                )
            }
            ForEach(bankDataManager.manualAccounts) { manual in
                let kind = String(describing: manual.accountType).lowercased()
                let counted = !(kind.contains("credit") || kind.contains("loan"))
                accountLine(name: manual.name, cents: Int((manual.balance * 100).rounded()), status: counted ? "counted" : "not a resource")
            }
        }
        .padding(14)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func excludedList(_ ssi: SSIStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Excluded").font(.headline).foregroundColor(.haloTextSecondary).accessibilityAddTraits(.isHeader)
            let res = ssi.resources
            if let able = res?.ableBalanceCents, able > 0 || dataManager.overview?.ssiProfile?.hasAbleAccount == true {
                accountLine(name: "ABLE account", cents: able, status: "excluded up to 100,000 dollars")
            }
            if let burial = res?.burialFundCents, burial > 0 {
                accountLine(name: "Designated burial fund", cents: burial, status: "excluded up to 1,500 dollars")
            }
            if (res?.ableBalanceCents ?? 0) == 0 && (res?.burialFundCents ?? 0) == 0 && dataManager.overview?.ssiProfile?.hasAbleAccount != true {
                Text("Nothing excluded. An ABLE account or a designated burial fund would be.")
                    .font(.subheadline).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func accountLine(name: String, cents: Int, status: String) -> some View {
        HStack {
            Text(name).font(.subheadline).foregroundColor(.haloTextPrimary)
            Spacer()
            Text(BudgetFormatter.cents(cents)).font(.subheadline.weight(.semibold))
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(VoiceOverFormatter.dollars(cents)), \(status).")
    }

    private var counselorButton: some View {
        Button { InAppBrowser.open(ProfileExplainer.wipaURL) } label: {
            Label("Talk to a free benefits counselor", systemImage: "person.wave.2")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
    }

    private func spokenDate(_ iso: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMMM d"
        return out.string(from: d)
    }
}

/// Which account types count toward the SSI resource limit.
enum SSIAccountRule {
    static func counted(type: String) -> Bool {
        let t = type.lowercased()
        return !(t == "credit" || t == "loan")
    }
}

struct MonitorActionSheet: View {
    let action: ResourceMonitorView.MonitorAction
    let resources: SSIResources?
    @Environment(\.dismiss) private var dismiss

    private var explainer: ProfileExplainer {
        let move = resources?.spendOrMoveCents ?? 0
        switch action {
        case .moveToABLE:
            return ProfileExplainer(
                title: "Move to ABLE",
                lines: [
                    "Money in an ABLE account is excluded from the resource limit up to 100,000 dollars.",
                    move > 0
                        ? "Moving about \(VoiceOverFormatter.dollars(move)) before the 1st would put you safely under the limit. Estimate."
                        : "A transfer that posts before the 1st counts for that month's measurement.",
                    "Yearly contributions are capped at 20,000 dollars. Transfers between your own accounts are not income.",
                ]
            )
        case .spendingThatCounts:
            return ProfileExplainer(
                title: "Spending that counts",
                lines: [
                    "Paying for needs before the 1st lowers what Social Security counts: rent or mortgage paid early, utilities, groceries, medical bills, a needed repair, or a prepaid bill.",
                    move > 0
                        ? "About \(VoiceOverFormatter.dollars(move)) would need to go to needs, or into an ABLE account, to be safely under the limit. Estimate."
                        : "Keep receipts for anything large.",
                    "Giving money away or selling something for less than it's worth can be treated as a transfer and cause a penalty. When in doubt, ask a counselor first.",
                ],
                linkTitle: "Talk to a free benefits counselor",
                linkURL: ProfileExplainer.wipaURL
            )
        }
    }

    var body: some View {
        ProfileExplainerSheet(explainer: explainer) { dismiss() }
    }
}
