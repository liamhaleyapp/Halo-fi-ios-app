//
//  ResourceAlertBanner.swift
//  Halo-fi-IOS
//
//  The Benefits tab's only mention of the SSI resource limit (Liam,
//  2026-09-04): the counter itself lives on the Money tab's balance card;
//  here an alert appears at the top ONLY when resources are in the watch
//  band (75 %), the act band (95 %) or over the limit. Nothing renders
//  while on track. State is carried by words, never color alone. Opens
//  the Resource monitor.
//

import SwiftUI

struct ResourceAlertBanner: View {
    let resources: SSIResources

    struct Copy: Equatable {
        let title: String
        let line: String
        let tone: ScreenReaderSummaryHeader.Tone
    }

    /// Nil while on track — the banner does not exist then.
    static func copy(for res: SSIResources) -> Copy? {
        let current = VoiceOverFormatter.dollars(res.currentCents)
        let limit = VoiceOverFormatter.dollars(res.limitCents)
        var measures = ""
        if let days = res.daysUntilMeasurement {
            measures = " Social Security measures in \(days == 1 ? "1 day" : "\(days) days")."
        }
        switch res.effectiveStatus {
        case "over":
            return Copy(title: "Over the SSI resource limit", line: "\(current) of \(limit).\(measures) Estimate.", tone: .act)
        case "critical":
            return Copy(title: "Act now on your SSI resources", line: "\(current) of \(limit).\(measures) Estimate.", tone: .act)
        case "warning":
            return Copy(title: "Getting close to your SSI resource limit", line: "\(current) of \(limit).\(measures) Estimate.", tone: .watch)
        default:
            return nil
        }
    }

    var body: some View {
        if let copy = Self.copy(for: resources) {
            NavigationLink(value: BenefitsHomeView.Route.resourceMonitor) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(copy.tone.color)
                        .frame(width: 42, height: 42)
                        .background(copy.tone.color.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.title).font(.headline).foregroundColor(.haloTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(copy.line).font(.subheadline).foregroundColor(.haloTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.haloTextTertiary).accessibilityHidden(true)
                }
                .padding(14)
                .frame(minHeight: 64)
                .background(copy.tone.color.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(copy.tone.color.opacity(0.5), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(HapticPlainButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(copy.title). \(copy.line)")
            .accessibilityHint("Opens the resource monitor.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("resourceAlertBanner")
        }
    }
}
