//
//  QuickActionChips.swift
//  Halo-fi-IOS
//
//  Shortcuts on the Agent tab: one "Shortcuts" button above the composer
//  opens a sheet of ready questions (the pre-rewrite Daily snapshot /
//  Weekly summary / Spending check plus the newer ones). Tapping one sends
//  it as text. Every row ≥56pt, one VoiceOver element each, Escape closes.
//

import SwiftUI

struct QuickActionChip: Identifiable {
    let id: String
    let title: String
    let prompt: String
    let icon: String
    /// Only for users in a benefits lane.
    var benefitsOnly: Bool = false

    static let v1: [QuickActionChip] = [
        QuickActionChip(id: "how-doing", title: "How am I doing this month?", prompt: "How am I doing this month? Give me my budget and spending in plain words.", icon: "chart.bar.fill"),
        QuickActionChip(id: "where-stand", title: "Where do I stand?", prompt: "Where do I stand right now? Balances, my resource limit if I have one, and anything I should know.", icon: "location.fill"),
        QuickActionChip(id: "daily", title: "Daily snapshot", prompt: "Give me a daily snapshot of my finances — balances, any recent transactions, and anything I should know about today.", icon: "sun.max.fill"),
        QuickActionChip(id: "weekly", title: "Weekly update", prompt: "Give me a weekly summary — how much did I spend this week, what were my biggest categories, and how am I tracking against my budget?", icon: "calendar"),
        QuickActionChip(id: "spending", title: "Spending check", prompt: "Do a spending check — where is my money going this month, what are my top spending categories, and are there any unusual charges?", icon: "magnifyingglass"),
        QuickActionChip(id: "log-expense", title: "Log a work expense", prompt: "I want to log a work expense.", icon: "briefcase.fill", benefitsOnly: true),
    ]

    static func available(benefitsLane: Bool) -> [QuickActionChip] {
        v1.filter { !$0.benefitsOnly || benefitsLane }
    }
}

/// The single button above the composer.
struct ShortcutsButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label("Shortcuts", systemImage: "bolt.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityHint("Opens a list of questions you can send with one tap.")
    }
}

struct ShortcutsSheet: View {
    let chips: [QuickActionChip]
    let onPick: (QuickActionChip) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(chips) { chip in
                        Button {
                            onPick(chip)
                            dismiss()
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
                .padding(20)
            }
            .background(Color.haloBackground.ignoresSafeArea())
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .accessibilityAction(.escape) { dismiss() }
        }
        .presentationDetents([.medium, .large])
    }
}
