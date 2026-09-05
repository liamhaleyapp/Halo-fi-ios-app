//
//  BalanceHeroCard.swift
//  Halo-fi-IOS
//
//  The Money tab's summary header: one number, one line, one tap. The
//  balance as a large figure with the account count, and — for SSI users —
//  a single sentence for the resource counter (Liam, 2026-09-04: the
//  balance card IS the resource counter; the Benefits tab only alerts).
//  Bars, band legends, the cash/owed split and the disclaimer live on the
//  Resource monitor the card opens (Liam, 2026-09-05: "the main screens
//  should never be this busy"). VoiceOver semantics are identical to
//  ScreenReaderSummaryHeader: one combined element, header trait, sort
//  priority 1000, the same identifier and the same verdict-first spoken
//  label. State is carried by a word, never color alone.
//

import SwiftUI

struct BalanceHeroCard: View {
    let summary: TabSummary
    let snapshot: MoneySnapshot
    let showsResources: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 40

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
                    .font(.title3.weight(.bold))
                    .foregroundColor(.haloTextPrimary)
                Spacer()
            }

            cashFigure

            if showsResources, let res = snapshot.resources {
                Text(resourceLine(res))
                    .font(.subheadline)
                    .foregroundColor(.haloTextPrimary)
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

    // MARK: - The number

    private var cashFigure: some View {
        let accounts = VoiceOverFormatter.count(snapshot.accountCount, singular: "account", plural: "accounts")
        let owed = max(0, snapshot.owedCents)
        return VStack(alignment: .leading, spacing: 2) {
            Text(Self.dollars(snapshot.cashCents))
                .font(.system(size: figureSize, weight: .bold, design: .rounded))
                .foregroundColor(.haloTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(owed > 0 ? "cash across \(accounts), \(Self.dollars(owed)) owed" : "cash across \(accounts)")
                .font(.caption)
                .foregroundColor(.haloTextSecondary)
        }
    }

    // MARK: - The line (SSI)

    /// "SSI limit: $1,214 of $2,000, on track. Estimate." — the state word
    /// comes from the same policy the spoken label uses.
    private func resourceLine(_ res: SSIResources) -> String {
        let (state, _) = TabSummaries.resourceState(res)
        return "SSI limit: \(Self.dollars(res.currentCents)) of \(Self.dollars(res.limitCents)), \(state). Estimate."
    }

    static func dollars(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}
