//
//  ActionButtonsSection.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct ActionButtonsSection: View {
    let onAction: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ActionButton(
                title: "Daily Snapshot",
                gradient: LinearGradient(
                    colors: [Color.indigo, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            ) {
                onAction("Give me a daily snapshot of my finances — balances, any recent transactions, and anything I should know about today.")
            }

            ActionButton(
                title: "Weekly Summary",
                gradient: LinearGradient(
                    colors: [Color.teal, Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            ) {
                onAction("Give me a weekly summary — how much did I spend this week, what were my biggest categories, and how am I tracking against my budget?")
            }

            ActionButton(
                title: "Spending Check",
                gradient: LinearGradient(
                    colors: [Color.teal.opacity(0.8), Color.cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            ) {
                onAction("Do a spending check — where is my money going this month, what are my top spending categories, and are there any unusual charges?")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 80)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ActionButtonsSection(onAction: { _ in })
    }
}
