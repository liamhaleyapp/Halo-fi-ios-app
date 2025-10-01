//
//  ActionButtonsSection.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct ActionButtonsSection: View {
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
        // TODO: Navigate to Daily Snapshot
      }
      
      ActionButton(
        title: "Weekly Summary",
        gradient: LinearGradient(
          colors: [Color.teal, Color.blue],
          startPoint: .leading,
          endPoint: .trailing
        )
      ) {
        // TODO: Navigate to Weekly Summary
      }
      
      ActionButton(
        title: "Spending Check",
        gradient: LinearGradient(
          colors: [Color.teal.opacity(0.8), Color.cyan],
          startPoint: .leading,
          endPoint: .trailing
        )
      ) {
        // TODO: Navigate to Spending Check
      }
      
      ActionButton(
        title: "Financial Coaching",
        gradient: LinearGradient(
          colors: [Color.white.opacity(0.9), Color.gray.opacity(0.7)],
          startPoint: .leading,
          endPoint: .trailing
        )
      ) {
        // TODO: Navigate to Financial Coaching
      }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 80)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    ActionButtonsSection()
  }
}
