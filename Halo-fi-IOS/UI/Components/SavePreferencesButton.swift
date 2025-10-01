//
//  SavePreferencesButton.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SavePreferencesButton: View {
  let onSave: () -> Void
  
  var body: some View {
    ActionButton(
      title: "Save Preferences",
      gradient: LinearGradient(
        colors: [.blue, .purple],
        startPoint: .leading,
        endPoint: .trailing
      )
    ) {
      onSave()
    }
    .accessibilityLabel("Save Preferences")
    .padding(.horizontal, 20)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    SavePreferencesButton(onSave: {})
  }
}
