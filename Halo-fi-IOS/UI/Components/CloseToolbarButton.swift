//
//  CloseToolbarButton.swift
//  Halo-fi-IOS
//
//  The toolbar "Cancel" / "Close" as an icon. At accessibility text sizes
//  the word truncated to "C…" (Liam, 2026-09-05). VoiceOver still hears
//  the word: the label is the accessibility label.
//

import SwiftUI

struct CloseToolbarButton: View {
    var label: String = "Close"
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "Closes this screen without saving.")
    }
}
