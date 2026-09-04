//
//  BalanceHeroCard.swift
//  Halo-fi-IOS
//
//  The Money tab's summary header with a visual: a large figure, a
//  cash-versus-owed bar (or, for SSI users, a resource gauge against the
//  limit with the 75 % / 95 % bands), and a soft tone-tinted gradient.
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

    private var extraDetail: String? {
        let sentences = summary.detail
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let rest = sentences.dropFirst(showsResources ? 1 : 2)
        return rest.isEmpty ? nil : rest.joined(separator: ". ") + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(tone.color).frame(width: 10, height: 10)
                Text(summary.verdict)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.haloTextPrimary)
                Spacer()
            }

            if showsResources, let res = snapshot.resources {
                resourceFigure(res)
                resourceGauge(res)
            } else {
                cashFigure
                cashOwedBar
            }

            // The first sentence of the detail is the figure the visual already
            // shows; only the extra sentences (measurement date, connections
            // needing attention) are drawn. VoiceOver hears the full label.
            if let extra = extraDetail {
                Text(extra)
                    .font(.subheadline)
                    .foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if summary.isEstimate {
                Text(ScreenReaderSummaryHeader.disclaimer)
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
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18).strokeBorder(tone.color.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(1000)
        .accessibilityIdentifier(ScreenReaderSummaryHeader.accessibilityID)
        .accessibilityLabel(spokenLabel)
    }

    // MARK: - Cash vs owed (everyone without a resource counter)

    private var cashFigure: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.dollars(snapshot.cashCents))
                .font(.system(size: figureSize, weight: .bold, design: .rounded))
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
        let total = max(1, cash + owed)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule().fill(Color.haloPositive)
                        .frame(width: max(barHeight, geo.size.width * CGFloat(cash) / CGFloat(total)))
                    if owed > 0 {
                        Capsule().fill(Color.orange)
                    }
                }
            }
            .frame(height: barHeight)
            HStack(spacing: 14) {
                legend(color: .haloPositive, text: "Cash \(Self.dollars(cash))")
                legend(color: .orange, text: "Owed \(Self.dollars(owed))")
            }
        }
    }

    // MARK: - Resource gauge (SSI)

    private func resourceFigure(_ res: SSIResources) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.dollars(res.currentCents))
                    .font(.system(size: figureSize, weight: .bold, design: .rounded))
                    .foregroundColor(.haloTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("of \(Self.dollars(res.limitCents))")
                    .font(.headline)
                    .foregroundColor(.haloTextSecondary)
            }
            Text("counted resources · Estimate")
                .font(.caption)
                .foregroundColor(.haloTextSecondary)
        }
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
            HStack(spacing: 14) {
                legend(color: .haloPositive, text: "Safe under 75%")
                legend(color: .orange, text: "Watch to 95%")
                legend(color: .haloNegative, text: "Act above")
            }
        }
    }

    // MARK: - Bits

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundColor(.haloTextSecondary).lineLimit(1).minimumScaleFactor(0.8)
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
