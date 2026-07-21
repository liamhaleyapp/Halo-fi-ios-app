//
//  HapticEngine.swift
//  Halo-fi-IOS
//
//  Game-quality haptic feedback for HaloFi. Wraps CoreHaptics so we
//  can play custom rhythmic patterns (Duolingo-class) instead of the
//  three-intensity vocabulary UIImpactFeedbackGenerator gives us.
//
//  WHY THIS EXISTS
//  - HaloFi's primary audience is blind / low-vision users. The
//    visual UI is secondary; tactile + audio cues carry the
//    information. iOS's basic light/medium/heavy impacts all "feel
//    the same" to first-time users — we need distinguishable
//    signatures for connecting / listening / processing / success
//    / error / "you've hit the end of a list."
//  - CoreHaptics gives us per-event sharpness + intensity envelopes
//    AND multi-event patterns (heartbeat pulse, ascending ticks,
//    cascading success, etc.). That's what makes Apple Pay and
//    Duolingo feel "alive."
//
//  FALLBACK BEHAVIOR
//  - CoreHaptics needs iPhone 8 or later AND a real device.
//    iPad, simulator, and older iPhones don't support it. We detect
//    via CHHapticEngine.capabilitiesForHardware().supportsHaptics
//    once at init and route to UIImpactFeedbackGenerator if unavail.
//
//  USAGE
//      Haptics.engine.play(.tickEdge)
//      Haptics.engine.startContinuous(.pulseThinking)
//      Haptics.engine.stopContinuous()
//
//  All call sites should use the named pattern enum — never build
//  CHHapticEvent inline. Keeps the vocabulary documented in one
//  place and makes it easy to A/B-tune intensity centrally.
//

import Foundation
import CoreHaptics
import UIKit

/// Catalog of named haptic patterns. Each one maps to either a
/// transient (single beat) or continuous (looping pulse) event.
/// Add new entries here and define them in `HapticEngine`'s pattern
/// builders — never define a pattern inline at a call site.
enum HapticPattern {
    // MARK: - Transient (single events)

    /// Quick crisp confirmation. Tap registered, button pressed.
    case tapCrisp
    /// Soft tap. Hover-style, low-stakes confirmation.
    case tapLight
    /// Single ascending tick — call with progress 0..1 to ramp
    /// sharpness as the user nears the end of a swipe.
    case tickAscending(progress: Double)
    /// Heavy thump + sharp transient. "You hit the wall — no more
    /// items in this direction." Pairs with a "boundary" sound.
    case tickEdge
    /// Three ascending beats — gold-standard "saved" feel.
    case successCascade
    /// Three sharp wobbles — distinct from system error, distinct
    /// from any tap.
    case errorShake
    /// Long curve for screen entry / state change. Subtle, ambient.
    case transitionSwoosh
    /// Heavy single thump — "I detected your interruption, switching."
    case bargeIn

    // MARK: - Continuous (looping pulses, must be stopped explicitly)

    /// Slow heartbeat — fading intensity, ~2 beats/sec. "I heard
    /// you and I'm thinking."
    case pulseThinking
    /// Tighter rhythm — "I'm hearing you right now, keep going."
    case pulseListening

    // MARK: - Notification feedback (mapped to the notification haptic)

    /// Used after a state transition where a NotificationFeedback
    /// shape (success/warning/error) makes more semantic sense
    /// than a custom pattern.
    case notification(UINotificationFeedbackGenerator.FeedbackType)

    var isContinuous: Bool {
        switch self {
        case .pulseThinking, .pulseListening: return true
        default: return false
        }
    }
}

@MainActor
final class HapticEngine {
    /// True when CoreHaptics is available AND the engine started
    /// successfully. Reads as `false` on iPad, simulator, older
    /// iPhones, and any hardware where the engine refused to start
    /// (rare; usually device-config issue).
    private(set) var isCoreHapticsAvailable: Bool = false

    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    /// What is ACTUALLY playing right now.
    private var continuousPattern: HapticPattern?
    /// What the app WANTS playing (driven by the conversation state
    /// machine via setContinuous). Kept separate from continuousPattern
    /// so that after an engine reset we can re-apply the desired pattern
    /// instead of silently dying, and a stale player can't block a restart.
    private var desiredContinuous: HapticPattern?
    /// Safety lease: a continuous pattern auto-stops if it isn't refreshed
    /// within this window. Guarantees a missed state transition degrades to
    /// SILENCE, never an endless buzz — the worst failure for a blind user.
    private var leaseTimer: Timer?
    private let continuousLeaseSeconds: TimeInterval = 45

    // System fallback generators — pre-allocated to avoid first-tap
    // latency. Apple recommends preparing them before use.
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    init() {
        prepareFallbackGenerators()
        startEngineIfSupported()
        observeAppLifecycle()
    }

    // MARK: - Public API

    /// Play a transient pattern (single beat). Continuous patterns
    /// are no-ops here — call startContinuous instead.
    func play(_ pattern: HapticPattern) {
        guard !pattern.isContinuous else { return }

        if isCoreHapticsAvailable, let engine = engine {
            do {
                let events = makeTransientEvents(for: pattern)
                let pattern = try CHHapticPattern(events: events, parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                return
            } catch {
                Logger.warning("HapticEngine: CoreHaptics play failed (\(error)); falling back.")
            }
        }
        playFallback(for: pattern)
    }

    /// Start a looping continuous pattern. Subsequent calls with a
    /// different pattern stop the prior loop. Idempotent for the
    /// same pattern (no-op if already running).
    func startContinuous(_ pattern: HapticPattern) {
        guard pattern.isContinuous else {
            // Caller misused the API; play once instead.
            play(pattern)
            return
        }
        if continuousPattern == pattern { return }
        stopContinuous()

        guard isCoreHapticsAvailable, let engine = engine else {
            // No CoreHaptics — fall back to a periodic timer + light
            // impacts. Less rich but still gives the user "I'm
            // working" feedback.
            startContinuousFallback(pattern: pattern)
            return
        }

        do {
            let events = makeContinuousEvents(for: pattern)
            let chPattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makeAdvancedPlayer(with: chPattern)
            player.loopEnabled = true
            try player.start(atTime: CHHapticTimeImmediate)
            continuousPlayer = player
            continuousPattern = pattern
        } catch {
            Logger.warning("HapticEngine: continuous pattern failed (\(error)); falling back.")
            startContinuousFallback(pattern: pattern)
        }
    }

    /// Stop any continuous pattern. Safe to call when nothing is
    /// playing.
    func stopContinuous() {
        leaseTimer?.invalidate()
        leaseTimer = nil
        if let player = continuousPlayer {
            do {
                try player.stop(atTime: CHHapticTimeImmediate)
            } catch {
                // The player refused to stop — it may still be looping.
                // Restart the whole engine as a fail-safe so the device
                // can't buzz forever (the catastrophic failure for a blind
                // user); the restart re-applies the desired pattern.
                Logger.warning("HapticEngine: continuous stop failed (\(error)); restarting engine")
                Task { @MainActor [weak self] in
                    try? await self?.engine?.stop()
                    try? self?.engine?.start()
                }
            }
            continuousPlayer = nil
        }
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        continuousPattern = nil
    }

    // MARK: - Single choke point for continuous haptics

    /// The ONLY method the conversation state machine should call to drive
    /// continuous feedback. Pass a continuous pattern to run it, or nil to
    /// stop. Diffs against what's playing (no-op if unchanged) and arms the
    /// safety lease so a missed transition can never leave the device
    /// buzzing indefinitely.
    func setContinuous(_ pattern: HapticPattern?) {
        desiredContinuous = (pattern?.isContinuous == true) ? pattern : nil
        applyContinuous()
    }

    /// Reconcile what's playing with `desiredContinuous`.
    private func applyContinuous() {
        guard let pattern = desiredContinuous else {
            stopContinuous()
            return
        }
        startContinuous(pattern)  // diffs internally (no-op if same)
        armLease()
    }

    /// (Re)start the auto-stop safety lease for the active pattern.
    private func armLease() {
        leaseTimer?.invalidate()
        guard desiredContinuous != nil else { return }
        leaseTimer = Timer.scheduledTimer(
            withTimeInterval: continuousLeaseSeconds, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.continuousPattern != nil else { return }
                Logger.warning("HapticEngine: continuous lease expired (\(self.continuousLeaseSeconds)s) — auto-stopping to prevent a stuck loop")
                self.desiredContinuous = nil
                self.stopContinuous()
            }
        }
    }

    // MARK: - Engine lifecycle

    private func startEngineIfSupported() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            isCoreHapticsAvailable = false
            return
        }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            // The engine resets when the audio session is interrupted
            // (phone call, route change). Restart on reset so the
            // next pattern still plays.
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    // The reset invalidated any live player. Clear the
                    // ACTUAL state (so the idempotency guard can't block a
                    // restart), restart the engine, then re-apply whatever
                    // pattern the app still wants — resume, not silently die.
                    self.continuousPlayer = nil
                    self.continuousPattern = nil
                    try? self.engine?.start()
                    self.applyContinuous()
                }
            }
            engine.stoppedHandler = { [weak self] _ in
                // System stopped us (background, route change). Drop the
                // dead player/pattern; observeAppLifecycle re-applies the
                // desired pattern on foreground.
                Task { @MainActor in
                    self?.continuousPlayer = nil
                    self?.continuousPattern = nil
                }
            }
            try engine.start()
            self.engine = engine
            self.isCoreHapticsAvailable = true
        } catch {
            Logger.warning("HapticEngine: CoreHaptics init failed (\(error)). Using UIKit fallback.")
            isCoreHapticsAvailable = false
        }
    }

    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Stop the loop but KEEP the desired pattern so it can
                // resume on foreground if the state machine still wants it.
                self?.stopContinuous()
                // Use the async overload of CHHapticEngine.stop()
                // since we're already inside a Task. The completion-
                // handler variant otherwise generates a "consider
                // using asynchronous alternative" warning under
                // recent SDKs.
                try? await self?.engine?.stop()
            }
        }
        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                try? self.engine?.start()
                // Resume whatever the app still wants playing.
                self.applyContinuous()
            }
        }
    }

    private func prepareFallbackGenerators() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        rigidImpact.prepare()
        softImpact.prepare()
        selection.prepare()
        notification.prepare()
    }

    // MARK: - Pattern builders (CoreHaptics)

    /// Single-event transient patterns. Sharpness ~ pitch / clickiness;
    /// intensity ~ volume / strength.
    private func makeTransientEvents(for pattern: HapticPattern) -> [CHHapticEvent] {
        switch pattern {
        case .tapCrisp:
            return [event(intensity: 0.7, sharpness: 0.85)]

        case .tapLight:
            return [event(intensity: 0.4, sharpness: 0.55)]

        case .tickAscending(let progress):
            // Ramp sharpness with progress so each tick sounds a
            // touch higher than the last. Intensity stays modest so
            // a long swipe doesn't fatigue. progress is Double for
            // ergonomics at the call site; cast to Float here since
            // CHHapticEventParameter.value wants Float.
            let clamped = Float(max(0.0, min(1.0, progress)))
            return [event(
                intensity: 0.45 + (clamped * 0.25),
                sharpness: 0.30 + (clamped * 0.65)
            )]

        case .tickEdge:
            // Heavy thump + immediate sharp transient. The thump is
            // the "wall," the transient is the "click off it."
            return [
                event(intensity: 1.0, sharpness: 0.20, time: 0.0),
                event(intensity: 0.6, sharpness: 1.0, time: 0.05),
            ]

        case .successCascade:
            // Three ascending beats over ~250ms. Same intensity,
            // rising sharpness — tonal lift without volume creep.
            return [
                event(intensity: 0.7, sharpness: 0.40, time: 0.00),
                event(intensity: 0.7, sharpness: 0.65, time: 0.10),
                event(intensity: 0.85, sharpness: 0.95, time: 0.22),
            ]

        case .errorShake:
            // Three sharp wobbles, rapid but with breathing room.
            return [
                event(intensity: 0.8, sharpness: 0.85, time: 0.00),
                event(intensity: 0.8, sharpness: 0.85, time: 0.08),
                event(intensity: 0.8, sharpness: 0.85, time: 0.16),
            ]

        case .transitionSwoosh:
            // Continuous-style 0.4s curve — rises then falls.
            return [
                continuousEvent(intensity: 0.3, sharpness: 0.6, duration: 0.40),
            ]

        case .bargeIn:
            // Single heavy thump. "Got it, switching."
            return [event(intensity: 0.9, sharpness: 0.5)]

        case .notification:
            // Handled in playFallback (uses system NotificationFeedback).
            return []

        case .pulseThinking, .pulseListening:
            // Continuous patterns; not reachable here (early return
            // in play() guards on isContinuous). Defensive empty.
            return []
        }
    }

    /// Looping continuous patterns. Built with CHHapticEvent.eventType
    /// .hapticContinuous and short repeating durations so loopEnabled
    /// produces the heartbeat / pulse rhythm.
    private func makeContinuousEvents(for pattern: HapticPattern) -> [CHHapticEvent] {
        switch pattern {
        case .pulseThinking:
            // ~2 beats/sec. Each beat is a fading transient over
            // 0.18s, then 0.32s silence inside the 0.5s loop window.
            return [
                event(intensity: 0.55, sharpness: 0.45, time: 0.00),
                event(intensity: 0.30, sharpness: 0.45, time: 0.18),
            ]

        case .pulseListening:
            // ~3 beats/sec. Subtler than thinking — confirms input
            // is being received without nagging.
            return [
                event(intensity: 0.35, sharpness: 0.55, time: 0.00),
            ]

        default:
            return []
        }
    }

    // MARK: - Helpers

    private func event(
        intensity: Float,
        sharpness: Float,
        time: TimeInterval = 0
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    private func continuousEvent(
        intensity: Float,
        sharpness: Float,
        duration: TimeInterval
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: 0,
            duration: duration
        )
    }

    // MARK: - Fallback path

    private var fallbackTimer: Timer?

    private func playFallback(for pattern: HapticPattern) {
        switch pattern {
        case .tapCrisp:           rigidImpact.impactOccurred()
        case .tapLight:           lightImpact.impactOccurred()
        case .tickAscending:      selection.selectionChanged()
        case .tickEdge:           heavyImpact.impactOccurred()
        case .successCascade:     notification.notificationOccurred(.success)
        case .errorShake:         notification.notificationOccurred(.error)
        case .transitionSwoosh:   softImpact.impactOccurred()
        case .bargeIn:            heavyImpact.impactOccurred()
        case .notification(let t): notification.notificationOccurred(t)
        case .pulseThinking, .pulseListening: break  // handled by timer
        }
    }

    private func startContinuousFallback(pattern: HapticPattern) {
        let interval: TimeInterval = (pattern == .pulseListening) ? 0.33 : 0.5
        continuousPattern = pattern
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if pattern == .pulseListening {
                    self.lightImpact.impactOccurred(intensity: 0.5)
                } else {
                    self.softImpact.impactOccurred(intensity: 0.6)
                }
            }
        }
        fallbackTimer = timer
    }

    deinit {
        fallbackTimer?.invalidate()
    }
}

// MARK: - Hashable conformance for HapticPattern

extension HapticPattern: Equatable {
    static func == (lhs: HapticPattern, rhs: HapticPattern) -> Bool {
        switch (lhs, rhs) {
        case (.tapCrisp, .tapCrisp),
             (.tapLight, .tapLight),
             (.tickEdge, .tickEdge),
             (.successCascade, .successCascade),
             (.errorShake, .errorShake),
             (.transitionSwoosh, .transitionSwoosh),
             (.bargeIn, .bargeIn),
             (.pulseThinking, .pulseThinking),
             (.pulseListening, .pulseListening):
            return true
        case let (.tickAscending(a), .tickAscending(b)):
            return a == b
        case let (.notification(a), .notification(b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Singleton accessor + legacy convenience API
//
// Older call sites (Shared/Helpers/Haptics.swift, Phase 11 Track C)
// used Haptics.success() / .error() / .warning() / .tap() — keep
// those entry points so we don't have to migrate ~15 callers, but
// route them through the new engine so they get CoreHaptics
// patterns on supported hardware. New code should prefer
// Haptics.engine.play(.namedPattern) for richer choice.

@MainActor
enum Haptics {
    static let engine = HapticEngine()

    /// "The thing happened" — saving a deduction, confirming a
    /// candidate, completing an action. Routes to the
    /// success-cascade CoreHaptics pattern (three ascending beats)
    /// instead of the basic notification haptic.
    static func success() {
        engine.play(.successCascade)
    }

    /// "The thing didn't happen" — server rejected, validation
    /// failed, network error. Routes to the error-shake pattern.
    static func error() {
        engine.play(.errorShake)
    }

    /// "Something needs your attention." Stays on the system
    /// warning notification haptic since CoreHaptics' transient
    /// vocabulary doesn't have a clean three-beat warning shape
    /// distinct from .successCascade.
    static func warning() {
        engine.play(.notification(.warning))
    }

    /// Light tap — confirm a button press registered before the
    /// next view appears or VoiceOver announces.
    static func tap() {
        engine.play(.tapCrisp)
    }
}
