//
//  ReadableContentWidth.swift
//  Halo-fi-IOS
//
//  App Store Guideline 4 (iPad): caps a screen's content column at a
//  readable width and centers it, so the iPhone-designed layout doesn't
//  stretch edge-to-edge on iPad. Backgrounds stay full-bleed because the
//  outer frame still expands to fill the screen.
//

import SwiftUI

struct ReadableContentWidth: ViewModifier {
    /// 672pt ≈ UIKit's readableContentGuide on a portrait 11" iPad.
    var maxWidth: CGFloat = 672

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Apply to the top-level content container inside a screen (e.g. the
    /// VStack inside a ScrollView), NOT to the screen itself — the screen's
    /// background should keep filling the full window.
    func readableContentWidth(_ maxWidth: CGFloat = 672) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth))
    }
}
