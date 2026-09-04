//
//  MicButton.swift
//  Halo-fi-IOS
//
//  Large 120pt microphone button for voice-first interaction.
//  Features:
//  - Dynamic label that changes based on state
//  - Pulse animation when listening
//  - Full accessibility support
//

import SwiftUI

struct MicButton: View {
    // Scales with Dynamic Type (App Store Guideline 4).
    @ScaledMetric(relativeTo: .largeTitle) private var micIconSize: CGFloat = 50
    let state: ConversationState
    let isEnabled: Bool
    let onTap: () -> Void
    /// Hands-free only — when true the button renders as an obvious
    /// mute toggle (mic.slash icon, gray gradient, no pulse) instead
    /// of the state-driven appearance. Lets the user tell at a glance
    /// that tapping will affect their mic, not Halo's flow.
    var appearMuted: Bool = false

    @State private var pulseAnimation = false

    // Button size
    private let buttonSize: CGFloat = 120
    private let pulseSize: CGFloat = 140

    var body: some View {
        VStack(spacing: 16) {
            // Mic button with pulse
            Button(action: {
                // Immediate tactile confirmation — fires synchronously
                // on tap, BEFORE the WebSocket / mic spin-up that can
                // take a few hundred ms. Real-device complaint was
                // "you have to wait for a half a second before the
                // voice agent starts" — the gap felt like dead air.
                // tapCrisp gives the user "I registered your tap" the
                // moment their finger comes off, then the
                // state-transition haptic from AudioFeedbackService
                // takes over once the connection lands.
                Haptics.engine.play(.tapCrisp)
                onTap()
            }) {
                ZStack {
                    // Pulse ring while actively listening — suppressed
                    // when shown as a mute toggle so the visual signal
                    // matches the action (no recording = no pulse).
                    if state == .listening && !appearMuted {
                        pulseRing
                    }

                    // Main button
                    mainButton

                    // Icon
                    buttonIcon
                }
            }
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.5)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)

            // Dynamic label below button
            Text(state.displayText)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(labelColor)
                .accessibilityHidden(true) // Already in button label
        }
        .onAppear {
            updatePulseAnimation()
        }
        .onChange(of: state) { _, _ in
            updatePulseAnimation()
        }
        .onChange(of: appearMuted) { _, _ in
            updatePulseAnimation()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var pulseRing: some View {
        Circle()
            .stroke(Color.blue.opacity(0.3), lineWidth: 4)
            .frame(width: pulseSize, height: pulseSize)
            .scaleEffect(pulseAnimation ? 1.3 : 1.0)
            .opacity(pulseAnimation ? 0.0 : 1.0)
            .animation(
                .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: false),
                value: pulseAnimation
            )
    }

    @ViewBuilder
    private var mainButton: some View {
        Circle()
            .fill(buttonGradient)
            .frame(width: buttonSize, height: buttonSize)
            .shadow(
                color: shadowColor.opacity(0.5),
                radius: 20
            )
    }

    @ViewBuilder
    private var buttonIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: micIconSize, weight: .medium))
            .foregroundColor(.white)
            .accessibilityHidden(true)
    }

    // MARK: - Computed Properties

    private var buttonGradient: LinearGradient {
        if appearMuted {
            return LinearGradient(
                colors: [Color(white: 0.45), Color(white: 0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        switch state {
        case .listening, .speaking:
            return LinearGradient(
                colors: [.red, .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .processing, .connecting:
            return LinearGradient(
                colors: [.orange, .yellow],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [.blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var shadowColor: Color {
        if appearMuted { return .gray }
        switch state {
        case .listening, .speaking:
            return .red
        case .processing, .connecting:
            return .orange
        default:
            return .blue
        }
    }

    private var iconName: String {
        if appearMuted { return "mic.slash.fill" }
        switch state {
        case .listening:
            return "waveform"
        case .processing, .connecting:
            return "ellipsis"
        case .speaking:
            return "stop.fill"
        default:
            return "mic.fill"
        }
    }

    private var labelColor: Color {
        switch state {
        case .listening, .speaking, .error:
            return .red
        case .processing, .connecting:
            return .orange
        default:
            return .secondary
        }
    }

    private var accessibilityLabel: String {
        if appearMuted { return "Mic muted" }
        switch state {
        case .listening:
            return "Stop listening"
        case .processing:
            return "Processing"
        case .speaking:
            return "Stop speaking"
        default:
            return "Start listening"
        }
    }

    private var accessibilityHint: String {
        if appearMuted { return "Double tap to unmute your microphone" }
        switch state {
        case .listening:
            return "Double tap to stop recording"
        case .processing:
            return "Please wait"
        case .speaking:
            return "Double tap to skip this message"
        default:
            return "Double tap to start speaking to Halo"
        }
    }

    // MARK: - Animation

    private func updatePulseAnimation() {
        pulseAnimation = (state == .listening) && !appearMuted
    }
}

// MARK: - Compact Variant (for text mode)

struct MicButtonCompact: View {
    let state: ConversationState
    let isEnabled: Bool
    let onTap: () -> Void
    /// The Agent tab's ONLY voice entry: purple, larger, labelled "Talk to Halo".
    var prominent: Bool = false

    private var iconName: String {
        switch state {
        case .listening:
            return "waveform"
        case .speaking:
            return "stop.fill"
        default:
            return "mic.fill"
        }
    }

    private var iconColor: Color {
        switch state {
        case .listening, .speaking:
            return .red
        default:
            return .blue
        }
    }

    private var accessibilityLabelText: String {
        switch state {
        case .listening:
            return "Stop listening"
        case .speaking:
            return "Stop speaking"
        default:
            return prominent ? "Talk to Halo" : "Switch to voice"
        }
    }

    private var accessibilityHintText: String {
        switch state {
        case .speaking:
            return "Double tap to skip this message"
        default:
            return "Double tap to use voice input"
        }
    }

    var body: some View {
        Button(action: onTap) {
            if prominent && state != .listening && state != .speaking {
                Image(systemName: iconName)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(Circle())
            } else {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: prominent ? 48 : 44, height: prominent ? 48 : 44)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.3)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        MicButton(state: .idle, isEnabled: true) { }

        MicButton(state: .listening, isEnabled: true) { }

        MicButton(state: .processing, isEnabled: false) { }

        MicButton(state: .speaking, isEnabled: false) { }

        HStack {
            MicButtonCompact(state: .idle, isEnabled: true) { }
            MicButtonCompact(state: .listening, isEnabled: true) { }
            MicButtonCompact(state: .speaking, isEnabled: true) { }
            MicButtonCompact(state: .idle, isEnabled: false) { }
        }
    }
    .padding()
}
