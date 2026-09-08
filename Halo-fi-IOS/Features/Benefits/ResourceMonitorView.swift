//
//  ResourceMonitorView.swift
//  Halo-fi-IOS
//
//  The SSI resource monitor screen (WP4), grown from BudgetView's old
//  ssiSection. Per-account counted list, excluded list with reasons,
//  alerts, and educational actions: About ABLE · Understanding resources ·
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
                        if let proj = resources.projection {
                            projectionSection(proj)
                        }
                    }
                    if let alerts = dataManager.overview?.ssiAlerts, !alerts.isEmpty {
                        ForEach(alerts) { entry in SSIAlertBanner(entry: entry) }
                    }
                    countedAccounts
                    excludedList(ssi)
                    if let income = ssi.income {
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
            } else {
                detail += " This is an estimate of today's resources, not a payment decision."
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

    // MARK: - Expected by the 1st (2026-09-05)

    private func projectionSection(_ proj: SSIProjection) -> some View {
        let date = TabSummaries.spokenDate(proj.measurementDateIso)
        let tone: ScreenReaderSummaryHeader.Tone = proj.band == "over" || proj.band == "critical" ? .act : proj.band == "warning" ? .watch : .positive
        return VStack(alignment: .leading, spacing: 8) {
            Text("Expected by \(date)").font(.headline).foregroundColor(.haloTextSecondary).accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Circle().fill(tone.color).frame(width: 10, height: 10).accessibilityHidden(true)
                Text("About \(BudgetFormatter.cents(proj.projectedCents)) of \(BudgetFormatter.cents(proj.limitCents)), \(proj.stateWords).")
                    .font(.body.weight(.semibold)).foregroundColor(.haloTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            ForEach(Array(proj.inflows.enumerated()), id: \.offset) { _, item in
                projectionRow(item, sign: "+")
            }
            ForEach(Array(proj.outflows.enumerated()), id: \.offset) { _, item in
                projectionRow(item, sign: "−")
            }
            if proj.inflows.isEmpty && proj.outflows.isEmpty {
                Text("Nothing expected before then that HaloFi knows about.")
                    .font(.subheadline).foregroundColor(.haloTextSecondary)
            }
            if proj.unconfirmedBillCount > 0 {
                Text("\(VoiceOverFormatter.count(proj.unconfirmedBillCount, singular: "possible bill is", plural: "possible bills are")) waiting for a yes or no on the Money tab.")
                    .font(.caption).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Estimate. Confidence: \(proj.confidence).").font(.caption2).foregroundColor(.haloTextTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func projectionRow(_ item: SSIProjection.Item, sign: String) -> some View {
        HStack {
            Text(item.label).font(.subheadline).foregroundColor(.haloTextPrimary).lineLimit(1)
            Spacer()
            Text("\(sign)\(BudgetFormatter.cents(item.cents))").font(.subheadline.weight(.semibold)).foregroundColor(sign == "+" ? .haloPositive : .haloTextPrimary)
            Text(TabSummaries.spokenDate(item.expectedDateIso)).font(.caption).foregroundColor(.haloTextSecondary)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label), \(sign == "+" ? "plus" : "minus") \(VoiceOverFormatter.dollars(item.cents)), \(TabSummaries.spokenDate(item.expectedDateIso)).")
    }

    // MARK: - Actions (Watch / Act)

    private func actions(_ resources: SSIResources) -> some View {
        VStack(spacing: 10) {
            if userManager.benefitsProfile.hasAbleAccount == true {
                actionButton("About ABLE accounts", icon: "arrow.down.to.line.circle") { explainer = .moveToABLE }
            }
            actionButton("Understanding resources", icon: "cart") { explainer = .spendingThatCounts }
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
        switch action {
        case .moveToABLE:
            return ProfileExplainer(
                title: "About ABLE accounts",
                lines: [
                    "ABLE accounts can have special treatment under SSI resource rules.",
                    "An account balance or transfer alone does not determine eligibility. Contribution limits and other rules may apply.",
                    "A free benefits counselor can explain how the rules apply to your situation.",
                ],
                linkTitle: "Talk to a free benefits counselor",
                linkURL: ProfileExplainer.wipaURL
            )
        case .spendingThatCounts:
            return ProfileExplainer(
                title: "Understanding resources",
                lines: [
                    "Social Security measures resources at the start of a month. Today's balance may differ from that amount.",
                    "The Watch and Act labels are HaloFi reminders to review your information. They do not set a spending requirement or a different resource limit.",
                    "A free benefits counselor can explain what counts and which records may be useful.",
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
