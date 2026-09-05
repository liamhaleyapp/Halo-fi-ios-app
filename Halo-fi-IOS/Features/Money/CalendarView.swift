//
//  CalendarView.swift
//  Halo-fi-IOS
//
//  Money → Calendar (2026-09-05): the month as a list of days, one VoiceOver
//  element per item, day headings for the rotor. No grid — a grid is
//  hostile to a screen reader; the day list IS the calendar. Every amount
//  is an estimate and the screen says so. Editing lives in Income / Bills.
//

import SwiftUI

struct CalendarView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(UserManager.self) private var userManager
    @State private var month: String? = nil       // nil = current
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var focus: Bool

    private var cal: CalendarMonth? { dataManager.calendar(for: month) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let cal {
                    ScreenReaderSummaryHeader(
                        verdict: cal.monthLabel,
                        detail: cal.spoken ?? summaryLine(cal),
                        isEstimate: true,
                        tone: .neutral,
                        visualDetail: summaryLine(cal)
                    )
                    monthNav(cal)
                    if cal.days.isEmpty {
                        Text("Nothing confirmed for this month yet. Answer the deposit and bill questions on the Money tab and they show up here.")
                            .font(.subheadline).foregroundColor(.haloTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).haloCard()
                    }
                    ForEach(cal.days) { day in
                        daySection(day)
                    }
                    Text("Estimate. Built from what you confirmed; Social Security makes all actual decisions.")
                        .font(.caption).foregroundColor(.haloTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if userManager.capabilities.showsBenefitsLane {
                        Button { InAppBrowser.open(ProfileExplainer.wipaURL) } label: {
                            Label("Talk to a free benefits counselor", systemImage: "person.wave.2")
                                .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Opens the free counselor finder inside HaloFi.")
                    }
                } else if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(DesignTokens.ToneText.act)
                    Button("Try again") { Task { await load() } }.buttonStyle(.bordered).frame(minHeight: 44)
                } else {
                    ProgressView("Building your month…")
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 100)
            .readableContentWidth()
        }
        .background(Color.haloBackground.ignoresSafeArea())
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await load(force: true)
            UIAccessibility.post(notification: .announcement, argument: "Updated.")
        }
        .task { await load() }
        .onChange(of: month) { _, _ in Task { await load(); focus = true } }
    }

    private func summaryLine(_ cal: CalendarMonth) -> String {
        var s = "\(VoiceOverFormatter.dollars(cal.totals.expectedInCents)) expected in, \(VoiceOverFormatter.dollars(cal.totals.expectedOutCents)) going out."
        if let n = cal.next, let d = n.date {
            s += " Next: \(n.label), \(TabSummaries.spokenDate(d))."
        }
        return s
    }

    private func monthNav(_ cal: CalendarMonth) -> some View {
        HStack {
            Button { month = shift(cal.month, by: -1) } label: {
                Label("Previous month", systemImage: "chevron.left").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(cal.monthLabel).font(.haloRowTitle).foregroundColor(.haloTextPrimary).accessibilityHidden(true)
            Spacer()
            Button { month = shift(cal.month, by: 1) } label: {
                Label("Next month", systemImage: "chevron.right").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next month")
        }
    }

    private func shift(_ key: String, by delta: Int) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return key }
        var m = parts[1] + delta, y = parts[0]
        if m < 1 { m = 12; y -= 1 } else if m > 12 { m = 1; y += 1 }
        return String(format: "%04d-%02d", y, m)
    }

    private func daySection(_ day: CalendarDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayTitle(day))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.haloTextSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(day.items) { item in itemRow(item, day: day) }
        }
    }

    private func dayTitle(_ day: CalendarDay) -> String {
        let spoken = TabSummaries.spokenDate(day.date)
        return day.isToday ? "Today, \(spoken)" : spoken
    }

    private func itemRow(_ item: CalendarItem, day: CalendarDay) -> some View {
        let tint: Color = {
            switch item.kind {
            case "income": return .haloPositive
            case "deadline": return .orange
            case "subscription": return .indigo
            default: return .teal
            }
        }()
        let icon: String = {
            switch item.kind {
            case "income": return "arrow.down.circle.fill"
            case "deadline": return "calendar.badge.exclamationmark"
            case "subscription": return "repeat.circle.fill"
            default: return "calendar.badge.clock"
            }
        }()
        let amount = item.cents == 0 ? "" : (item.confidence == "about" ? "about " : "") + BudgetFormatter.cents(item.cents)
        let state: String = {
            switch item.status {
            case "arrived": return "arrived"
            case "paid": return "paid"
            case "due": return "due"
            case "past": return ""
            default: return "expected"
            }
        }()
        return HStack(spacing: 14) {
            HaloIconTile(icon: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label).font(.haloRowTitle).foregroundColor(.haloTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text([amount, state].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundColor(.haloTextSecondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(minHeight: 64)
        .haloCard(tint: item.kind == "deadline" && item.status == "due" ? .orange : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label)" + (amount.isEmpty ? "" : ", \(amount)") + (state.isEmpty ? "" : ", \(state)") + ".")
    }

    private func load(force: Bool = false) async {
        guard !UITestArchetype.isActive else { return }
        if !force, cal != nil { return }
        isLoading = true
        errorMessage = nil
        do {
            try await dataManager.loadCalendar(month: month)
        } catch {
            errorMessage = "Couldn't build the month. \(error.localizedDescription)"
        }
        isLoading = false
    }
}
