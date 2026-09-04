//
//  QuickActionChips.swift
//  Halo-fi-IOS
//
//  Shortcuts above the composer on the Agent tab. Stacked full-width
//  buttons, never a horizontal scroll (that fought VoiceOver's swipe
//  order and the tab gesture). Shown open when the thread is empty;
//  once there are messages they collapse into one "Shortcuts" button and
//  re-collapse after a tap. Every button ≥56pt with its own label.
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

struct QuickActionStack: View {
    var chips: [QuickActionChip] = QuickActionChip.v1
    /// True when the thread already has messages: start collapsed.
    let collapsible: Bool
    let onTap: (QuickActionChip) -> Void

    @State private var expanded = false

    private var showsList: Bool { !collapsible || expanded }

    var body: some View {
        VStack(spacing: 8) {
            if collapsible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Label(expanded ? "Hide shortcuts" : "Shortcuts", systemImage: expanded ? "chevron.down" : "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityHint(expanded ? "Hides the three shortcuts." : "Shows three questions you can send with one tap.")
            }
            if showsList {
                ForEach(chips) { chip in
                    Button {
                        onTap(chip)
                        if collapsible { withAnimation { expanded = false } }
                    } label: {
                        Label(chip.title, systemImage: chip.icon)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(.horizontal, 14)
                            .background(Color.haloSecondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(HapticPlainButtonStyle())
                    .accessibilityLabel(chip.title)
                    .accessibilityHint("Sends this question to Halo as text.")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shortcuts")
    }
}
