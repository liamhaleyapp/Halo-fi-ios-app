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
    let state: ConversationState
    let isEnabled: Bool
    let onTap: () -> Void

    @State private var pulseAnimation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Button size
    private let buttonSize: CGFloat = 120
    private let pulseSize: CGFloat = 140

    var body: some View {
        VStack(spacing: 16) {
            // Mic button with pulse
            Button(action: onTap) {
                ZStack {
                    // Pulse ring when listening
                    if state == .listening {
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
        .onChange(of: state) { _, newState in
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
                reduceMotion ? nil : .easeInOut(duration: 1.0)
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
            .font(.largeTitle)
            .foregroundColor(.white)
            .accessibilityHidden(true)
    }

    // MARK: - Computed Properties

    private var buttonGradient: LinearGradient {
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
        pulseAnimation = (state == .listening)
    }
}

// MARK: - Compact Variant (for text mode)

struct MicButtonCompact: View {
    let state: ConversationState
    let isEnabled: Bool
    let onTap: () -> Void

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
            return "Switch to voice"
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
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray5))
                .clipShape(Circle())
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
