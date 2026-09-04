//
//  BenefitsHomeView.swift
//  Halo-fi-IOS
//
//  The Benefits tab (WP4). Shown for everyone: benefit users get the
//  resource monitor and their lane; everyone gets the work-expense log and
//  the education cards. Reading order:
//    a. Summary header ("Your SSI" / "Your SSDI" / "Work expenses")
//    b. Resource monitor row (SSI only) → ResourceMonitorView
//    c. Work expenses row → WorkExpensesView
//    d. Learn cards (static in V1)
//    e. Last element, always: "Talk to a free benefits counselor"
//  SSI and SSDI are never blended into one number. BWE rows render
//  visible-but-locked when statutory blindness is unverified.
//

import SwiftUI

struct BenefitsHomeView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(UserManager.self) private var userManager
    @Environment(\.openURL) private var openURL

    @State private var navigationPath = NavigationPath()
    @State private var hasAppeared = false

    enum Route: Hashable {
        case resourceMonitor, workExpenses
        /// WP6 — nil month = the previous month.
        case monthlyPackage(String?)
        case monthEndReview(String)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.haloBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        header
                        if userManager.capabilities.showsResourceCounter {
                            resourceMonitorRow
                        }
                        workExpensesRow
                        monthlyPackageRow
                        if userManager.capabilities.bweLocked {
                            lockedBWERow
                        }
                        if userManager.capabilities.showsSSDILane && !userManager.capabilities.showsResourceCounter {
                            ssdiLaneRow
                        }
                        learnCards
                        counselorButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                    .readableContentWidth()
                }
                .refreshable { await dataManager.refresh() }
            }
            .navigationTitle("Benefits")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .resourceMonitor: ResourceMonitorView()
                case .workExpenses: WorkExpensesView()
                case .monthlyPackage(let month): MonthlyPackageView(initialMonth: month)
                case .monthEndReview(let month): MonthEndReviewView(month: month)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetBenefitsNavigation)) { _ in
                if !navigationPath.isEmpty { navigationPath.removeLast(navigationPath.count) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .workExpenseDraftRequested)) { _ in
                openWorkExpenses()
            }
            .onReceive(NotificationCenter.default.publisher(for: .receiptShared)) { _ in
                openWorkExpenses()
            }
            // WP6 — a tapped reminder notification lands on the right screen.
            .onReceive(NotificationCenter.default.publisher(for: .ssiReminderOpened)) { note in
                let kind = note.userInfo?["kind"] as? String ?? ""
                let month = note.userInfo?["month"] as? String ?? ""
                if !navigationPath.isEmpty { navigationPath.removeLast(navigationPath.count) }
                switch kind {
                case "submit_package": navigationPath.append(Route.monthlyPackage(month.isEmpty ? nil : month))
                case "month_end_review": navigationPath.append(Route.monthEndReview(month.isEmpty ? MonthKey.current : month))
                default: navigationPath.append(Route.workExpenses)
                }
            }
            .task {
                guard !hasAppeared else { return }
                hasAppeared = true
                if dataManager.shouldRefresh { await dataManager.refresh() }
                if WorkExpenseHandoff.shared.pending != nil || ReceiptHandoff.shared.pending != nil {
                    openWorkExpenses()
                }
            }
        }
    }

    private func openWorkExpenses() {
        if navigationPath.isEmpty { navigationPath.append(Route.workExpenses) }
    }

    // MARK: - a. Header

    private var expensesImpact: Int {
        dataManager.ssiManualDeductions.reduce(0) { $0 + ($1.estimatedCheckImpactCents ?? 0) }
    }

    private var summary: TabSummary {
        let base = TabSummaries.benefits(
            capabilities: userManager.capabilities,
            ssi: dataManager.overview?.ssiStatus,
            expensesThisMonth: dataManager.ssiManualDeductions.count,
            expensesTotalCents: dataManager.ssiManualDeductions.reduce(0) { $0 + $1.amountCents },
            expensesImpactCents: expensesImpact
        )
        // WP6 — reminders ride on the header so the first swipe says it.
        let count = dataManager.ssiReminders.count
        guard count > 0 else { return base }
        let line = " " + VoiceOverFormatter.count(count, singular: "reminder", plural: "reminders") + "."
        return TabSummary(verdict: base.verdict, detail: base.detail + line, isEstimate: base.isEstimate,
                          tone: base.tone == .neutral ? .watch : base.tone)
    }

    private var header: some View {
        ScreenReaderSummaryHeader(
            verdict: summary.verdict,
            detail: summary.detail,
            isEstimate: summary.isEstimate,
            tone: summary.tone
        )
    }

    // MARK: - b. Resource monitor row

    private var resourceMonitorRow: some View {
        let res = dataManager.overview?.ssiStatus.resources
        let (word, tone) = res.map(TabSummaries.resourceVerdict) ?? ("Resources", .neutral)
        var line = "Resource monitor."
        if let res {
            line = "\(VoiceOverFormatter.dollars(res.currentCents)) of \(VoiceOverFormatter.dollars(res.limitCents)). \(word)."
            if let iso = res.measurementDateIso, let days = res.daysUntilMeasurement {
                line += " SSA measures on \(Self.spokenDate(iso)), in \(days == 1 ? "1 day" : "\(days) days")."
            }
        }
        return row(
            title: "Resource monitor",
            icon: "gauge.with.dots.needle.33percent",
            tone: tone,
            line: line,
            estimate: true,
            route: .resourceMonitor
        )
    }

    // MARK: - c. Work expenses row

    private var workExpensesRow: some View {
        row(
            title: "Work expenses",
            icon: "briefcase.fill",
            tone: .neutral,
            line: TabSummaries.expensesLine(
                dataManager.ssiManualDeductions.count,
                dataManager.ssiManualDeductions.reduce(0) { $0 + $1.amountCents },
                expensesImpact
            ),
            estimate: expensesImpact > 0,
            route: .workExpenses
        )
    }

    // MARK: - c2. Monthly package row (WP6)

    private var monthlyPackageRow: some View {
        let submit = dataManager.ssiReminders.first { $0.kind == "submit_package" }
        let line = submit.map { "\($0.title). \($0.body)" }
            ?? "Last month's SSA-795 package: cover, ledger and receipts. Share, print, or send it to yourself."
        return row(
            title: "Monthly package",
            icon: "doc.text.fill",
            tone: submit == nil ? .neutral : .watch,
            line: line,
            estimate: true,
            route: .monthlyPackage(submit?.month)
        )
    }

    private var lockedBWERow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").foregroundColor(.haloTextSecondary).frame(width: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Blind Work Expenses — locked").font(.headline).foregroundColor(.haloTextPrimary)
                Text("Locked until Social Security's record confirms statutory blindness. Here's how to check: your award letter or a BPQY from 1-800-772-1213. Update it in Settings, Benefits profile.")
                    .font(.subheadline).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var ssdiLaneRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").foregroundColor(.haloTextSecondary).frame(width: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("SSDI work incentives — coming soon").font(.headline).foregroundColor(.haloTextPrimary)
                Text("Trial Work Period and substantial-gainful-activity tracking arrive in a later update. Your work expenses still count as IRWE today.")
                    .font(.subheadline).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.haloSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    // MARK: - d. Learn cards

    private var learnCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Learn").font(.headline).foregroundColor(.haloTextSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(LearnCard.v1) { card in
                NavigationLink {
                    LearnCardView(card: card)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: card.icon).foregroundColor(.blue).frame(width: 36).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title).font(.body.weight(.semibold)).foregroundColor(.haloTextPrimary)
                            Text(card.summary).font(.caption).foregroundColor(.haloTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.haloTextTertiary).accessibilityHidden(true)
                    }
                    .padding(12)
                    .frame(minHeight: 56)
                    .background(Color.haloSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(HapticPlainButtonStyle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(card.title). \(card.summary)")
                .accessibilityHint("Opens a short explainer.")
            }
        }
        .padding(.top, 8)
    }

    // MARK: - e. Counselor (always last)

    private var counselorButton: some View {
        Button {
            var url = ProfileExplainer.wipaURL
            if let state = userManager.benefitsProfile.stateCode, !state.isEmpty,
               let withState = URL(string: "https://choosework.ssa.gov/findhelp/result?option=stateList&state=\(state)") {
                url = withState
            }
            openURL(url)
        } label: {
            Label("Talk to a free benefits counselor", systemImage: "person.wave.2")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Opens the Social Security counselor finder for your state.")
        .padding(.top, 8)
    }

    // MARK: - Row builder

    private func row(title: String, icon: String, tone: ScreenReaderSummaryHeader.Tone, line: String, estimate: Bool, route: Route) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundColor(tone.color).frame(width: 36).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundColor(.haloTextPrimary)
                    Text(line).font(.subheadline).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if estimate {
                        Text("Estimate").font(.caption2).foregroundColor(.haloTextTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.haloTextTertiary).accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 64)
            .background(Color.haloSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(HapticPlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(line)\(estimate ? " Estimate." : "")")
        .accessibilityAddTraits(.isButton)
    }

    private static func spokenDate(_ iso: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMMM d"
        return out.string(from: d)
    }
}

// MARK: - Learn cards (static V1)

struct LearnCard: Identifiable {
    let id: String
    let icon: String
    let title: String
    let summary: String
    let body: [String]

    static let v1: [LearnCard] = [
        LearnCard(
            id: "resource-limit", icon: "gauge.with.dots.needle.33percent",
            title: "The resource limit",
            summary: "Why the 1st of the month matters.",
            body: [
                "Social Security counts what you own on the first moment of the 1st of each month. For one person the limit is 2,000 dollars; for a couple who both receive SSI it is 3,000 dollars.",
                "Checking, savings and cash count. An ABLE account is excluded up to 100,000 dollars, and a designated burial fund up to 1,500 dollars.",
                "Being over on the 1st means no SSI payment for that month. Getting back under within 12 months restores it.",
            ]
        ),
        LearnCard(
            id: "bwe-irwe", icon: "briefcase.fill",
            title: "BWE and IRWE",
            summary: "Work expenses that keep more of your check.",
            body: [
                "An Impairment-Related Work Expense, IRWE, is something you pay for because of your disability so you can work: medication, a device, therapy, a service animal, assistive technology. It comes off your countable income before the 50 percent step, so it is worth about half its cost on your check.",
                "A Blind Work Expense, BWE, is any work expense for someone Social Security lists as statutorily blind: transportation to work, guide dog costs, readers, taxes withheld, union dues, meals at work. It comes off after the 50 percent step, so it is worth its full cost.",
                "Keep every receipt. Social Security asks for proof.",
            ]
        ),
        LearnCard(
            id: "reporting", icon: "calendar",
            title: "Reporting wages",
            summary: "By the 6th, every month.",
            body: [
                "Report wages for the previous month by the 6th. Wage reports through SSA's app or phone line cannot include BWE or IRWE, so the expense package HaloFi prepares goes to your field office separately.",
                "HaloFi never sends anything to Social Security. You file; the app prepares, reminds, and logs.",
            ]
        ),
        LearnCard(
            id: "counselor", icon: "person.wave.2",
            title: "Free benefits counseling",
            summary: "WIPA counselors answer the questions apps can't.",
            body: [
                "Work Incentives Planning and Assistance, WIPA, is a free Social Security program. A counselor can look at your exact record and answer deeming, trust, overpayment and \"should I\" questions.",
                "Find one at choosework.ssa.gov/findhelp, or call the Ticket to Work help line at 1-866-968-7842.",
            ]
        ),
    ]
}

struct LearnCardView: View {
    let card: LearnCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(card.title)
                    .font(.title.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(card.body.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.body)
                        .foregroundColor(.haloTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(ScreenReaderSummaryHeader.disclaimer)
                    .font(.caption)
                    .foregroundColor(.haloTextSecondary)
            }
            .padding(20)
        }
        .readableContentWidth()
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
