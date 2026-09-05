//
//  ScreenReaderSummaryHeader.swift
//  Halo-fi-IOS
//
//  The first thing VoiceOver reads on every tab (WP4, Andrew's rule):
//  one combined element, header trait, highest sort priority, verdict in
//  words BEFORE any number. Visually a compact card at the top.
//
//  Every computed benefits number that appears here carries "Estimate"
//  (hard product rule 3) — pass `isEstimate: true` and the label ends with
//  the disclaimer line.
//

import SwiftUI

struct ScreenReaderSummaryHeader: View {
    /// The verdict, in words ("On track", "Watch", "Act now").
    let verdict: String
    /// The numbers and detail, spoken after the verdict.
    let detail: String
    /// Adds the "Estimate for education only…" line to the label.
    var isEstimate: Bool = false
    /// Accent for the visual chip; state is never conveyed by color alone —
    /// the verdict word is always present.
    var tone: Tone = .neutral
    /// A shorter line to DRAW when `detail` is long (the spoken label keeps
    /// the full detail). Main screens stay concise; the rest is one tap
    /// deeper (Liam, 2026-09-05).
    var visualDetail: String? = nil

    enum Tone {
        case neutral, positive, watch, act

        var color: Color {
            switch self {
            case .neutral: return .haloTextSecondary
            case .positive: return .haloPositive
            case .watch: return .orange
            case .act: return .haloNegative
            }
        }
    }

    static let disclaimer = "Estimate for education only — Social Security makes all actual decisions."
    static let accessibilityID = "screenSummaryHeader"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tone.color)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(verdict)
                    .font(.haloTitle)
                    .foregroundColor(.haloTextPrimary)
                Spacer()
            }
            Text(visualDetail ?? detail)
                .font(.body)
                .foregroundColor(.haloTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if isEstimate {
                Text("Estimate. Social Security makes all actual decisions.")
                    .font(.caption)
                    .foregroundColor(.haloTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [tone.color.opacity(tone == .neutral ? 0.08 : 0.18), Color.haloSecondaryBackground],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tone.color.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilitySortPriority(1000)
        .accessibilityIdentifier(Self.accessibilityID)
        .accessibilityLabel(spokenLabel)
    }

    var spokenLabel: String {
        var parts = ["\(verdict).", detail]
        if isEstimate { parts.append(Self.disclaimer) }
        return parts.joined(separator: " ")
    }
}
