//
//  AboutContentSections.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//  Updated with Accessibility, Security sections and enhanced content.
//

import SwiftUI

// MARK: - What is Halo Fi Section
struct WhatIsHaloFiSection: View {
    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("What is Halo Fi?")
                    .font(.headline)
                    .foregroundColor(.gray)

                Text("Your voice-first financial assistant, designed to make understanding your finances simple, clear, and accessible. Halo Fi empowers everyone, especially those who are visually impaired, with intuitive and supportive tools built around voice and ease of use.")
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Our Mission Section
struct OurMissionSection: View {
    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Our Mission")
                    .font(.headline)
                    .foregroundColor(.gray)

                Text("To bring visibility to personal finances through accessible and intelligent technology \u{2014} empowering everyone, especially those with visual impairments.")
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Accessibility Features Section
struct AccessibilityFeaturesSection: View {
    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Accessibility")
                    .font(.headline)
                    .foregroundColor(.gray)

                featureRow(icon: "waveform", color: .blue, text: "Voice-first design for hands-free use")
                featureRow(icon: "eye.fill", color: .green, text: "Full VoiceOver support")
                featureRow(icon: "textformat.size", color: .orange, text: "Dynamic Type for adjustable text sizes")
                featureRow(icon: "circle.lefthalf.filled", color: .purple, text: "High contrast mode")
                featureRow(icon: "hand.raised.fill", color: .teal, text: "Respects Reduce Motion preferences")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Accessibility features: voice-first design, VoiceOver support, Dynamic Type, high contrast mode, and Reduce Motion support")
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.body)
                .frame(width: 24)
            Text(text)
                .font(.body)
                .foregroundColor(.white)
            Spacer()
        }
    }
}

// MARK: - Data Security Section
struct DataSecuritySection: View {
    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Data Security")
                    .font(.headline)
                    .foregroundColor(.gray)

                featureRow(icon: "lock.shield.fill", color: .teal, text: "AES-256 encryption at rest and in transit")
                featureRow(icon: "key.fill", color: .yellow, text: "Bank credentials never stored")
                featureRow(icon: "checkmark.seal.fill", color: .green, text: "Plaid-secured bank connections")
                featureRow(icon: "eye.slash.fill", color: .blue, text: "Read-only access to financial data")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Data security: AES-256 encryption, bank credentials never stored, Plaid-secured connections, read-only access")
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.body)
                .frame(width: 24)
            Text(text)
                .font(.body)
                .foregroundColor(.white)
            Spacer()
        }
    }
}

// MARK: - Legal Section
struct LegalSection: View {
    let onTermsTap: () -> Void
    let onPrivacyTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            aboutButton(title: "Terms of Service", icon: "doc.text.fill", color: .blue, action: onTermsTap)
                .accessibilityHint("Double-tap to view terms of service")
            aboutButton(title: "Privacy Policy", icon: "hand.raised.fill", color: .purple, action: onPrivacyTap)
                .accessibilityHint("Double-tap to view privacy policy")
        }
    }

    private func aboutButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.body)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
        }
    }
}

// MARK: - Support Section
struct SupportSection: View {
    let onHelpTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            aboutButton(title: "Help & Feedback", icon: "questionmark.circle.fill", color: .green, action: onHelpTap)
                .accessibilityHint("Double-tap to get help or send feedback")
        }
    }

    private func aboutButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.body)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
        }
    }
}

// MARK: - App Version Section
struct AppVersionSection: View {
    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        HStack {
            Text("Version \(version) (\(build))")
                .font(.footnote)
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityLabel("App version \(version), build \(build)")
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 12) {
                WhatIsHaloFiSection()
                OurMissionSection()
                AccessibilityFeaturesSection()
                DataSecuritySection()
                LegalSection(onTermsTap: {}, onPrivacyTap: {})
                SupportSection(onHelpTap: {})
                AppVersionSection()
            }
            .padding()
        }
    }
}
