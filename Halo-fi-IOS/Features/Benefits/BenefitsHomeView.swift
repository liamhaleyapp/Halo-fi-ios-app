//
//  BenefitsHomeView.swift
//  Halo-fi-IOS
//
//  The Benefits tab (WP4, reshaped 2026-09-04). Exists for SSI / SSDI users
//  and for anyone who has not answered the questionnaire yet; answered
//  "no SSI, no SSDI" users have no Benefits tab (MainTabView.visibleTabs).
//  Reading order:
//    a. Summary header — the MOST URGENT item first (over the limit > act
//       now > package due > receipts needed > watch band > lane line)
//    b. Resource alert banner (SSI, only in watch / act / over) → monitor
//    c. Work expenses row → WorkExpensesView
//    d. Monthly package row, locked-BWE / SSDI cards, Learn
//    e. "Your benefits profile" row (the answers, each tappable to change)
//       and "Redo the questionnaire"
//    f. Last element, always: "Talk to a free benefits counselor"
//  The resource COUNTER lives on the Money tab's balance card. SSI and SSDI
//  are never blended into one number.
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
        case learn
        case benefitsProfile
        case questionnaire
    }

    private var lane: UserCapabilities.Lane { userManager.capabilities.lane }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.haloBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        header
                        switch lane {
                        case .ssi:
                            if let res = dataManager.overview?.ssiStatus.resources {
                                ResourceAlertBanner(resources: res)
                            }
                            workExpensesRow
                            monthlyPackageRow
                            if userManager.capabilities.bweLocked {
                                lockedBWERow
                            }
                            if userManager.capabilities.showsSSDILane {
                                ssdiLaneRow
                            }
                            learnRow
                            benefitsProfileSummaryRow
                            redoQuestionnaireRow
                            counselorButton
                        case .ssdi:
                            workExpensesRow
                            monthlyPackageRow
                            ssdiLaneRow
                            learnRow
                            benefitsProfileSummaryRow
                            redoQuestionnaireRow
                            counselorButton
                        case .none:
                            startQuestionnaireRow
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                    .readableContentWidth()
                }
                .refreshable {
                    // The lane can change on the server (an answer edited on
                    // another device, a capabilities fix); pull-to-refresh
                    // must be able to change what this tab IS, not only its
                    // numbers.
                    async let caps: Void = userManager.refreshCapabilities()
                    async let data: Void = dataManager.refresh()
                    _ = await (caps, data)
                }
            }
            .navigationTitle("Benefits")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .resourceMonitor: ResourceMonitorView()
                case .workExpenses: WorkExpensesView()
                case .monthlyPackage(let month): MonthlyPackageView(initialMonth: month)
                case .monthEndReview(let month): MonthEndReviewView(month: month)
                case .learn: LearnListView(lane: lane)
                case .benefitsProfile: BenefitsProfileView()
                case .questionnaire:
                    BenefitsQuestionnaireView(onFinished: {
                        if !navigationPath.isEmpty { navigationPath.removeLast(navigationPath.count) }
                    })
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
        guard lane != .none else { return }
        if navigationPath.isEmpty { navigationPath.append(Route.workExpenses) }
    }

    // MARK: - Not answered yet: the only row is the way to start

    private var startQuestionnaireRow: some View {
        row(
            title: "Start the benefits questionnaire",
            icon: "list.bullet.clipboard.fill",
            tone: .neutral,
            line: "About a minute, one tap per answer. This tab is built from what you tell us.",
            estimate: false,
            route: .questionnaire
        )
    }

    // MARK: - e. The answers behind one row, and the way to redo them

    private var benefitsProfileSummaryRow: some View {
        row(
            title: "Your benefits profile",
            icon: "person.text.rectangle.fill",
            tone: .neutral,
            line: BenefitsProfileView.overviewLine(capabilities: userManager.capabilities, profile: userManager.benefitsProfile),
            estimate: false,
            route: .benefitsProfile
        )
    }

    private var redoQuestionnaireRow: some View {
        NavigationLink(value: Route.questionnaire) {
            Label("Redo the questionnaire", systemImage: "arrow.counterclockwise")
                .font(.body.weight(.semibold))
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(HapticPlainButtonStyle())
        .accessibilityHint("Walks through every question again, one per screen.")
    }

    // MARK: - a. Header

    private var expensesImpact: Int {
        dataManager.ssiManualDeductions.reduce(0) { $0 + ($1.estimatedCheckImpactCents ?? 0) }
    }

    private var summary: TabSummary {
        TabSummaries.benefits(
            capabilities: userManager.capabilities,
            ssi: dataManager.overview?.ssiStatus,
            expensesThisMonth: dataManager.ssiManualDeductions.count,
            expensesTotalCents: dataManager.ssiManualDeductions.reduce(0) { $0 + $1.amountCents },
            expensesImpactCents: expensesImpact,
            reminders: dataManager.ssiReminders,
            needsReceiptCount: dataManager.ssiManualDeductions.filter { $0.resolvedMatchStatus == "needs_receipt" }.count
        )
    }

    private var header: some View {
        ScreenReaderSummaryHeader(
            verdict: summary.verdict,
            detail: summary.detail,
            isEstimate: summary.isEstimate,
            tone: summary.tone
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

    // MARK: - d. Learn (one row; the cards live on their own screen)

    private var learnRow: some View {
        let cards = LearnCard.cards(for: lane)
        return row(
            title: "Learn",
            icon: "book.fill",
            tone: .neutral,
            line: "\(VoiceOverFormatter.count(cards.count, singular: "short explainer", plural: "short explainers")): " + cards.map { $0.title.lowercased() }.joined(separator: ", ") + ".",
            estimate: false,
            route: .learn
        )
    }

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
            InAppBrowser.open(url)
        } label: {
            Label("Talk to a free benefits counselor", systemImage: "person.wave.2")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Opens the Social Security counselor finder for your state, inside the app. Close returns here.")
        .padding(.top, 8)
    }

    // MARK: - Row builder

    private func row(title: String, icon: String, tone: ScreenReaderSummaryHeader.Tone, line: String, estimate: Bool, route: Route) -> some View {
        let tint: Color = tone == .neutral ? .blue : tone.color
        return NavigationLink(value: route) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
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

}

// MARK: - Learn cards (static V1)

struct LearnCard: Identifiable {
    let id: String
    let icon: String
    let title: String
    let summary: String
    let body: [String]
    /// Which lanes may see this card. SSI-only content never reaches an
    /// SSDI user and vice versa.
    var lanes: Set<UserCapabilities.Lane> = [.ssi]

    static func cards(for lane: UserCapabilities.Lane) -> [LearnCard] {
        v1.filter { $0.lanes.contains(lane) }
    }

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
            id: "irwe", icon: "briefcase.fill",
            title: "IRWE and your SSDI",
            summary: "Work expenses that lower what counts toward the earnings limit.",
            body: [
                "An Impairment-Related Work Expense, IRWE, is something you pay for because of your disability so you can work: medication, a device, therapy, a service animal, assistive technology, rides you need because of your condition.",
                "For SSDI, IRWE come off your gross earnings before Social Security compares them to the substantial-gainful-activity limit. Logging them can keep a month under that line.",
                "Keep every receipt. Social Security asks for proof.",
            ],
            lanes: [.ssdi]
        ),
        LearnCard(
            id: "reporting", icon: "calendar",
            title: "Reporting wages",
            summary: "By the 6th, every month.",
            body: [
                "Report wages for the previous month by the 6th. Wage reports through SSA's app or phone line cannot include work expenses, so the expense package HaloFi prepares goes to your field office separately.",
                "HaloFi never sends anything to Social Security. You file; the app prepares, reminds, and logs.",
            ],
            lanes: [.ssi, .ssdi]
        ),
        LearnCard(
            id: "counselor", icon: "person.wave.2",
            title: "Free benefits counseling",
            summary: "WIPA counselors answer the questions apps can't.",
            body: [
                "Work Incentives Planning and Assistance, WIPA, is a free Social Security program. A counselor can look at your exact record and answer deeming, trust, overpayment and \"should I\" questions.",
                "Find one at choosework.ssa.gov/findhelp, or call the Ticket to Work help line at 1-866-968-7842.",
            ],
            lanes: [.ssi, .ssdi]
        ),
    ]
}

struct LearnListView: View {
    var lane: UserCapabilities.Lane = .ssi
    @Environment(\.openURL) private var openURL

    private var cards: [LearnCard] { LearnCard.cards(for: lane) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ScreenReaderSummaryHeader(
                    verdict: "Learn",
                    detail: "\(VoiceOverFormatter.count(cards.count, singular: "short explainer", plural: "short explainers")). Each one is a few paragraphs.",
                    tone: .neutral
                )
                ForEach(cards) { card in
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
                Button { InAppBrowser.open(ProfileExplainer.wipaURL) } label: {
                    Label("Talk to a free benefits counselor", systemImage: "person.wave.2")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Learn")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LearnCardView: View {
    let card: LearnCard
    @Environment(\.openURL) private var openURL

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
                Button { InAppBrowser.open(ProfileExplainer.wipaURL) } label: {
                    Label("Talk to a free benefits counselor", systemImage: "person.wave.2")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding(20)
        }
        .readableContentWidth()
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
