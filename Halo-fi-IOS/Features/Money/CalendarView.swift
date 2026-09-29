//
//  CalendarView.swift
//  Halo-fi-IOS
//
//  Money → Calendar (2026-09-05): the days ahead as a list, one VoiceOver
//  element per item, day headings for the rotor. No grid — a grid is
//  hostile to a screen reader; the day list IS the calendar. Every amount
//  carries its status. Recurring entries open the shared bill/subscription editor.
//  2026-09-28: 30-day windows from today instead of calendar months; rows
//  take the Recent-transactions look (logo, amount on the right).
//

import SwiftUI

struct CalendarView: View {
    @Environment(BudgetDataManager.self) private var dataManager
    @Environment(UserManager.self) private var userManager
    @State private var offsetDays = 0            // multiples of 30, never past windows
    @State private var errorMessage: String?
    @State private var selectedPayment: CalendarItem?
    @AccessibilityFocusState private var focus: Bool

    private var cal: CalendarMonth? { dataManager.calendar(offsetDays: offsetDays) }
    private var windowTitle: String { offsetDays == 0 ? "Next 30 days" : (cal?.windowLabel ?? "Later") }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                windowNav
                if let cal {
                    ScreenReaderSummaryHeader(
                        verdict: windowTitle,
                        detail: Self.summaryDetail(cal, offsetDays: offsetDays),
                        isEstimate: cal.estimate ?? false,
                        tone: .neutral
                    )
                    .accessibilityFocused($focus)
                    if cal.days.isEmpty {
                        Text("No payments confirmed for these dates. Review your income and bills to add expected activity.")
                            .font(.subheadline).foregroundColor(.haloTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading).haloCard()
                    }
                    ForEach(cal.days) { day in
                        daySection(day)
                    }
                } else if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(DesignTokens.ToneText.act)
                    Button("Try again") { Task { await load() } }.buttonStyle(.bordered).frame(minHeight: 44)
                } else {
                    ProgressView("Loading upcoming payments…")
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
        .onAppear { Diagnostics.screen("calendar") }
        .task { await load(force: true) }
        .onChange(of: offsetDays) { _, _ in Task { await load(); focus = true } }
        .sheet(item: $selectedPayment) { item in
            BillConfirmSheet(streamId: item.streamId ?? "", merchant: item.merchant ?? item.label, amountCents: item.cents,
                             frequencyLabel: "", nextExpected: nil, suggestedKind: item.kind) {
                Task { await load(force: true) }
            }
        }
    }

    /// "Next: Spotify, September 27. 3 payments, $412 going out in the next
    /// 7 days." The 7-day figures are counted here, from the days within
    /// today + 7; later windows count the whole window instead.
    static func summaryDetail(_ cal: CalendarMonth, offsetDays: Int = 0) -> String {
        var parts: [String] = []
        if let n = cal.next, let d = n.date {
            parts.append("Next: \(n.label), \(TabSummaries.spokenDate(d)).")
        }
        let outgoing = ["bill", "subscription", "card_payment"]
        let horizon: String? = {
            guard offsetDays == 0, let today = CalendarDates.ymd.date(from: cal.today),
                  let end = Calendar.current.date(byAdding: .day, value: 7, to: today) else { return nil }
            return CalendarDates.ymd.string(from: end)
        }()
        let days = horizon.map { end in cal.days.filter { $0.date >= cal.today && $0.date < end } } ?? cal.days
        let payments = days.flatMap(\.items).filter { outgoing.contains($0.kind) && $0.status != "paid" }
        let total = payments.reduce(0) { $0 + $1.cents }
        let when = horizon == nil ? "in these 30 days" : "in the next 7 days"
        parts.append("\(VoiceOverFormatter.count(payments.count, singular: "payment", plural: "payments")), \(VoiceOverFormatter.dollars(total)) going out \(when).")
        if cal.days.contains(where: { $0.items.contains(where: { $0.paymentVerified == false }) }) {
            parts.append("Some payments are unverified while a bank connection is unavailable.")
        }
        return parts.joined(separator: " ")
    }

    static func currentMonthKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f.string(from: Date())
    }

    private var windowNav: some View {
        HStack {
            Button { offsetDays = max(0, offsetDays - 30) } label: {
                Label("Previous 30 days", systemImage: "chevron.left").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous 30 days")
            .disabled(offsetDays == 0)
            Spacer()
            Text(cal?.windowLabel ?? windowTitle).font(.haloRowTitle).foregroundColor(.haloTextPrimary).accessibilityHidden(true)
            Spacer()
            Button { offsetDays += 30 } label: {
                Label("Next 30 days", systemImage: "chevron.right").labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next 30 days")
        }
    }

    private func daySection(_ day: CalendarDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayTitle(day))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.haloTextSecondary)
                .accessibilityHidden(true)
            ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in itemRow(item, day: day) }
        }
    }

    private func dayTitle(_ day: CalendarDay) -> String {
        let spoken = TabSummaries.spokenDate(day.date)
        return day.isToday ? "Today, \(spoken)" : spoken
    }

    @ViewBuilder
    private func itemRow(_ item: CalendarItem, day: CalendarDay) -> some View {
        if item.canManageRecurringPayment {
            Button { selectedPayment = item } label: { itemContent(item, day: day) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens payment details, including recording a cancellation.")
                .accessibilityAction(named: Text("Record cancellation")) { selectedPayment = item }
        } else {
            itemContent(item, day: day)
        }
    }

    private func itemContent(_ item: CalendarItem, day: CalendarDay) -> some View {
        let tint: Color = {
            switch item.kind {
            case "income": return .haloPositive
            case "deadline": return .orange
            case "subscription": return .indigo
            case "card_payment": return item.status == "overdue" ? .red : .orange
            default: return .teal
            }
        }()
        let icon: String = {
            switch item.kind {
            case "income": return "arrow.down.circle.fill"
            case "deadline": return "calendar.badge.exclamationmark"
            case "subscription": return "repeat.circle.fill"
            case "card_payment": return item.status == "overdue" ? "exclamationmark.circle.fill" : "creditcard.fill"
            default: return "calendar.badge.clock"
            }
        }()
        let amount = item.cents == 0 ? "" : (item.confidence == "about" ? "about " : "") + BudgetFormatter.cents(item.cents)
        let state = item.statusDescription
        return HaloRow {
            logo(item, icon: icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label).font(.haloRowTitle).foregroundColor(.haloTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let highlight = item.highlight { Text(highlight).font(.headline) }
                Text(state)
                    .font(.subheadline).foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                if !amount.isEmpty { Text(amount).font(.title3.bold()).foregroundColor(.haloTextPrimary) }
                Text(dayTitle(day)).font(.subheadline).foregroundColor(.haloTextSecondary)
            }
            if item.canManageRecurringPayment { HaloChevron() }
        }
        .padding(14)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .haloCard(tint: (item.kind == "deadline" && item.status == "due") ? .orange : (item.status == "overdue" ? .red : nil))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dayTitle(day)), \(item.label)" + (amount.isEmpty ? "" : ", \(amount)") + (state.isEmpty ? "" : ", \(state)") + (state.hasSuffix(".") ? "" : "."))
    }

    /// Merchant logo when the server has one, else the icon tile. Decorative.
    @ViewBuilder
    private func logo(_ item: CalendarItem, icon: String, tint: Color) -> some View {
        if let logoUrl = item.logoUrl, let url = URL(string: logoUrl) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                HaloIconTile(icon: icon, tint: tint)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .accessibilityHidden(true)
        } else {
            HaloIconTile(icon: icon, tint: tint).accessibilityHidden(true)
        }
    }

    private func load(force: Bool = false) async {
        guard !UITestArchetype.isActive else { return }
        if !force, cal != nil { return }
        errorMessage = nil
        do {
            try await dataManager.loadCalendar(offsetDays: offsetDays)
        } catch {
            errorMessage = "Couldn't build these 30 days. \(error.localizedDescription)"
        }
    }
}
