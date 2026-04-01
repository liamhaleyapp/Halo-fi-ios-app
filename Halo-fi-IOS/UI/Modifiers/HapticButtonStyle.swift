//
//  HapticButtonStyle.swift
//  Halo-fi-IOS
//
//  Global button style that adds haptic feedback to all button presses.
//

import SwiftUI

/// A button style that adds haptic feedback on press.
/// Uses sensoryFeedback modifier which doesn't interfere with navigation gestures.
struct HapticButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { oldValue, newValue in
                // Trigger haptic when button is pressed down
                return !oldValue && newValue
            }
    }
}

/// A plain button style that still provides haptic feedback.
/// Use this to replace `.buttonStyle(.plain)` while keeping haptics.
struct HapticPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { oldValue, newValue in
                // Trigger haptic when button is pressed down
                return !oldValue && newValue
            }
    }
}
