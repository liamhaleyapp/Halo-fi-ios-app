//
//  QuickActionChips.swift
//  Halo-fi-IOS
//
//  WP7 — prompt chips above the composer on the Agent tab. Each one sends
//  a text turn; nothing here requires talking to Halo, and every chip is a
//  ≥44pt button with its own VoiceOver label.
//

import SwiftUI

struct QuickActionChip: Identifiable {
    let id: String
    let title: String
    let prompt: String
    let icon: String

    static let v1: [QuickActionChip] = [
        QuickActionChip(id: "log-expense", title: "Log a work expense", prompt: "I want to log a work expense.", icon: "briefcase.fill"),
        QuickActionChip(id: "how-doing", title: "How am I doing this month?", prompt: "How am I doing this month? Give me my budget and spending in plain words.", icon: "chart.bar.fill"),
        QuickActionChip(id: "where-stand", title: "Where do I stand?", prompt: "Where do I stand right now? Balances, my resource limit if I have one, and anything I should know.", icon: "location.fill"),
    ]
}

struct QuickActionChips: View {
    var chips: [QuickActionChip] = QuickActionChip.v1
    let onTap: (QuickActionChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button { onTap(chip) } label: {
                        Label(chip.title, systemImage: chip.icon)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Color.haloSecondaryBackground)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(HapticPlainButtonStyle())
                    .accessibilityLabel(chip.title)
                    .accessibilityHint("Sends this question to Halo as text.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
    }
}
