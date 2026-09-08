//
//  BalanceHeroCard.swift
//  Halo-fi-IOS
//
//  The Money tab's summary header with a visual: the balance as a large
//  figure with a cash-versus-owed bar, and — for SSI users — the resource
//  counter underneath: the countable figure against the limit with the
//  75 % / 95 % bands (Liam, 2026-09-04: the balance card IS the resource
//  counter; the Benefits tab only alerts). A soft tone-tinted gradient.
//  VoiceOver semantics are identical to ScreenReaderSummaryHeader: one
//  combined element, header trait, sort priority 1000, the same identifier
//  and the same verdict-first spoken label. Every visual is hidden from
//  VoiceOver and every state is also carried by a word, never color alone.
//

import SwiftUI

struct BalanceHeroCard: View {
    let summary: TabSummary
    let snapshot: MoneySnapshot
    let showsResources: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 12

    private var tone: ScreenReaderSummaryHeader.Tone { summary.tone }

    private var spokenLabel: String {
        ScreenReaderSummaryHeader(
            verdict: summary.verdict, detail: summary.detail,
            isEstimate: summary.isEstimate, tone: summary.tone
        ).spokenLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(tone.color).frame(width: 10, height: 10)
                Text(summary.verdict)
                    .font(.haloTitle)
                    .foregroundColor(.haloTextPrimary)
                Spacer()
            }

            if snapshot.isLoading {
                loadingFigure
            } else {
                cashFigure
                cashOwedBar

            }

            if showsResources, !snapshot.isLoading, let res = snapshot.resources {
                resourceCounter(res)
            }

            // The figure already shows the first sentence of the detail; the
            // summary names what else is worth drawing (the resource line,
            // connections needing attention). VoiceOver hears the full label.
            if let subline = summary.subline {
                Text(subline)
                    .font(.subheadline)
                    .foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if summary.isEstimate {
                Text("Estimate. Social Security makes all actual decisions.")
                    .font(.caption)
                    .foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [tone.color.opacity(0.18), Color.haloSecondaryBackground],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tone.color.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(1000)
        .accessibilityIdentifier(ScreenReaderSummaryHeader.accessibilityID)
        .accessibilityLabel(spokenLabel)
    }

    // MARK: - Cash vs owed (everyone without a resource counter)

    /// First launch, nothing cached yet: keep the card's shape, say what
    /// is happening, and let the real figure replace it in place.
    private var loadingFigure: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("$ —")
                .font(.haloDisplay(figureSize))
                .foregroundColor(.haloTextSecondary)
            Text("fetching your balances")
                .font(.caption)
                .foregroundColor(.haloTextSecondary)
        }
    }

    private var cashFigure: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.dollars(snapshot.cashCents))
                .font(.haloDisplay(figureSize))
                .foregroundColor(.haloTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("cash across \(VoiceOverFormatter.count(snapshot.accountCount, singular: "account", plural: "accounts"))")
                .font(.caption)
                .foregroundColor(.haloTextSecondary)
        }
    }

    private var cashOwedBar: some View {
        let cash = max(0, snapshot.cashCents)
        let owed = max(0, snapshot.owedCents)
        let pending = max(0, snapshot.pending?.outflowCents ?? 0)
        return VStack(alignment: .leading, spacing: 8) {
            MoneySegmentsBar(amounts: [cash, owed, pending], colors: [.haloPositive, .haloNegative, .yellow], pendingIndex: 2)
                .frame(height: barHeight)
            VStack(alignment: .leading, spacing: 6) {
                MoneyBarLegend(color: .haloPositive, text: "Cash \(PendingBankActivity.money(cash))")
                MoneyBarLegend(color: .haloNegative, text: "Owed \(PendingBankActivity.money(owed))")
                if snapshot.pending != nil {
                    MoneyBarLegend(color: .yellow, text: "Pending \(PendingBankActivity.money(pending))", pending: true)
                }
            }
        }
    }

    // MARK: - Resource counter (SSI)

    private func resourceCounter(_ res: SSIResources) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .foregroundColor(tone.color)
                Text("SSI resource limit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.haloTextPrimary)
                Spacer()
                Text("\(Self.dollars(res.currentCents)) of \(Self.dollars(res.limitCents))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(tone.textColor)
            }
            resourceGauge(res)
        }
        .padding(.top, 4)
    }

    private func resourceGauge(_ res: SSIResources) -> some View {
        let pct = res.limitCents > 0 ? min(1.0, Double(res.currentCents) / Double(res.limitCents)) : 0
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.haloTextTertiary.opacity(0.25))
                    Capsule().fill(tone.color)
                        .frame(width: max(barHeight, geo.size.width * CGFloat(pct)))
                    // 75 % and 95 % band markers (Andrew's Safe / Watch / Act).
                    ForEach([0.75, 0.95], id: \.self) { mark in
                        Rectangle().fill(Color.haloTextPrimary.opacity(0.5))
                            .frame(width: 2, height: barHeight + 6)
                            .offset(x: geo.size.width * CGFloat(mark) - 1)
                    }
                }
            }
            .frame(height: barHeight)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    legend(color: .haloPositive, text: "Safe under 75%")
                    legend(color: .orange, text: "Watch to 95%")
                    legend(color: .haloNegative, text: "Act above")
                }
                VStack(alignment: .leading, spacing: 4) {
                    legend(color: .haloPositive, text: "Safe under 75%")
                    legend(color: .orange, text: "Watch to 95%")
                    legend(color: .haloNegative, text: "Act above")
                }
            }
        }
    }

    // MARK: - Bits

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundColor(.haloTextSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func dollars(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}



/// The same explicit split on total and category budget cards, including VoiceOver.
struct PendingSpendingBreakdown: View {
    let posted: Int?
    let pending: Int?
    var postedColor: Color = .haloPositive
    var body: some View {
        if let pending {
            VStack(alignment: .leading, spacing: 6) {
                if let posted { MoneyBarLegend(color: postedColor, text: "Spent \(PendingBankActivity.money(posted))") }
                MoneyBarLegend(color: .yellow, text: "Pending \(PendingBankActivity.money(pending))", pending: true)
            }
            .font(.subheadline)
            .foregroundStyle(Color.haloTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    static func spoken(posted: Int?, pending: Int?) -> String {
        guard let pending else { return "" }
        let postedLine = posted.map { " Spent \(PendingBankActivity.money($0))." } ?? ""
        return postedLine + " Pending \(PendingBankActivity.money(pending))."
    }
}


/// Decorative chart; its parent supplies one concise VoiceOver label.
/// Zero amounts have zero width. Over-budget charts normalize to total usage
/// so pending remains visible even when posted spending exceeds the limit.
struct MoneySegmentsBar: View {
    let amounts: [Int]
    let colors: [Color]
    var pendingIndex: Int

    static func fractions(_ amounts: [Int]) -> [Double] {
        let positive = amounts.map { max(0, Double($0)) }
        let total = positive.reduce(0, +)
        return positive.map { total > 0 ? $0 / total : 0 }
    }

    var body: some View {
        GeometryReader { geo in
            let fractions = Self.fractions(amounts)
            HStack(spacing: 0) {
                ForEach(amounts.indices, id: \.self) { index in
                    Rectangle().fill(colors[index])
                        .overlay { if index == pendingIndex { PendingHatch() } }
                        .frame(width: geo.size.width * fractions[index])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.haloTextTertiary.opacity(0.25))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.haloTextPrimary.opacity(0.55), lineWidth: 1))
        }
        .accessibilityHidden(true)
    }
}

struct PendingHatch: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: -size.height, through: size.width, by: 7) {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
            }
            context.stroke(path, with: .color(.black.opacity(0.65)), lineWidth: 1)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct MoneyBarLegend: View {
    let color: Color
    let text: String
    var pending = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color)
                .overlay { if pending { PendingHatch() } }
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.haloTextPrimary.opacity(0.55), lineWidth: 1))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(Color.haloTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BudgetUsageBar: View {
    let spent: Int
    let posted: Int?
    let pending: Int?
    let limit: Int
    var color: Color = .haloPositive
    var body: some View {
        MoneySegmentsBar(amounts: [posted ?? (spent - (pending ?? 0)), pending ?? 0, max(0, limit - spent)],
                         colors: [color, .yellow, Color.haloTextTertiary.opacity(0.25)], pendingIndex: 1)
    }
}
