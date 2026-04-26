//
//  BudgetQuickActionDrawer.swift
//  Halo-fi-IOS
//
//  Phase 11 Track B — first row a blind user encounters when the
//  Budget tab loads. Three actions cover the 80% case:
//    🎤 Ask Halo      — deep-link to the voice tab
//    ➕ Log expense   — open the manual deduction sheet
//    📢 Status        — re-speak the screen summary
//
//  Why a row of explicit buttons instead of a hidden gesture:
//  blind users discover features by swiping; an invisible
//  three-finger gesture is undiscoverable. Three labeled buttons
//  with VoiceOver hints meet users where they are.
//
//  Tap targets are 56pt tall (well above Apple's 44pt minimum)
//  with full-width hit areas. Icons are paired with text so
//  nothing depends on color alone.
//

import SwiftUI

struct BudgetQuickActionDrawer: View {
    let onLogExpense: () -> Void
    let onAskStatus: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            actionButton(
                title: "Log expense",
                systemImage: "plus.circle.fill",
                tint: .green,
                accessibilityHint: "Opens a form to log a Blind Work Expense, IRWE, or burial-fund deposit.",
                action: onLogExpense
            )
            actionButton(
                title: "What's my status?",
                systemImage: "mic.circle.fill",
                tint: .indigo,
                accessibilityHint: "Switches to the voice tab and asks Halo for a full SSI status update.",
                action: onAskStatus
            )
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            // Light haptic so the user feels confirmation that
            // their tap registered, even before the next view
            // appears or VoiceOver announces the state change.
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .padding(.horizontal, 12)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(tint)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(tint.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }
}
