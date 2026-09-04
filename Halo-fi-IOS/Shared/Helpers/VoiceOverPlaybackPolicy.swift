//
//  VoiceOverPlaybackPolicy.swift
//  Halo-fi-IOS
//
//  What Halo's own speech does while VoiceOver is running.
//
//  Halo speaking IS the product for many blind users, so the app must
//  never silently turn its voice off because a screen reader is on. The
//  user chooses, in Settings → Preferences → "When VoiceOver is on":
//    duck   — Halo keeps talking at reduced gain so VoiceOver stays
//             intelligible over it (default)
//    mute   — Halo's audio plays at zero gain; the transcript still
//             appears and the conversation flow (timing, state) is
//             unchanged, so VoiceOver can read Halo's words instead
//    normal — no change
//
//  Stored per device (VoiceOver is a per-device setting), so it is not
//  pushed to the backend preferences endpoint.
//

import Foundation
import UIKit

enum VoiceOverHaloBehavior: String, CaseIterable {
    case duck
    case mute
    case normal

    var title: String {
        switch self {
        case .duck: return "Duck Halo (quieter)"
        case .mute: return "Mute Halo (read transcript)"
        case .normal: return "Normal volume"
        }
    }
}

enum VoiceOverPlaybackPolicy {
    /// UserDefaults key shared with PreferencesView's @AppStorage.
    static let storageKey = "voiceOverHaloBehavior"

    /// Gain applied to Halo's speech while ducking.
    static let duckGain: Float = 0.35

    static var behavior: VoiceOverHaloBehavior {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return VoiceOverHaloBehavior(rawValue: raw) ?? .duck
    }

    static var isVoiceOverRunning: Bool {
        UIAccessibility.isVoiceOverRunning
    }

    /// Per-player gain (0...1) for Halo's own speech right now.
    static var speechGain: Float {
        guard isVoiceOverRunning else { return 1.0 }
        switch behavior {
        case .normal: return 1.0
        case .duck: return duckGain
        case .mute: return 0.0
        }
    }

    /// Earcons (state-change sounds) follow the same intent: quieter when
    /// ducking or muting so they never mask VoiceOver.
    static func earconGain(_ base: Float) -> Float {
        guard isVoiceOverRunning, behavior != .normal else { return base }
        return base * 0.5
    }
}
