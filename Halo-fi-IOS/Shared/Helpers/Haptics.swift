//
//  Haptics.swift
//  Halo-fi-IOS
//
//  Phase 11 Track C — single import point for the haptic
//  patterns the app uses. Blind users rely on haptics as a
//  primary feedback channel (alongside VoiceOver) — they tell
//  you a tap registered, a save succeeded, or something went
//  wrong without waiting for the announcement to finish.
//
//  Rules of thumb:
//    - .success: "the thing happened" — saving a deduction,
//      confirming a candidate, completing an action.
//    - .error:   "the thing didn't happen" — server rejected,
//      validation failed, network error.
//    - .warning: "something needs your attention" — used by
//      alert banners on appearance.
//    - .selection (UISelectionFeedbackGenerator): use for
//      lighter UI changes like picker scroll. Not in this enum.
//

import UIKit

enum Haptics {

    /// Fires only when the user has VoiceOver or haptics-capable
    /// hardware. Devices without taptic engine no-op silently.
    static func success() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }

    static func error() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.error)
    }

    static func warning() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
    }

    /// Light tap — confirm a button press registered before the
    /// next view appears or VoiceOver announces.
    static func tap() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }
}
