//
//  SaveProfileButton.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SaveProfileButton: View {
  let isEnabled: Bool
  let onSave: () -> Void
  
  var body: some View {
    ActionButton(
      title: "Save Changes",
      gradient: LinearGradient(
        colors: [Color.blue, Color.purple],
        startPoint: .leading,
        endPoint: .trailing
      )
    ) {
      onSave()
    }
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1.0 : 0.5)
    .padding(.horizontal, 20)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    VStack {
      SaveProfileButton(isEnabled: true, onSave: {})
      SaveProfileButton(isEnabled: false, onSave: {})
    }
  }
}
