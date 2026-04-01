//
//  InviteFriendsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//  Redesigned with native share sheet and improved referral display.
//

import SwiftUI
import UIKit

struct InviteFriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.haloHighContrast) private var highContrast

    @State private var showingCopied = false
    @State private var showingShareSheet = false

    private let referralCode = "HALO123"
    private let referralLink = "https://halofi.app/ref/user123"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                incentiveSection
                referralCodeSection
                shareButton
                howItWorksSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationTitle("Invite Friends")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [
                "Join me on HaloFi \u{2014} your voice-first financial assistant! Use my code \(referralCode) to get started: \(referralLink)"
            ])
        }
    }

    // MARK: - Incentive Section

    private var incentiveSection: some View {
        VStack(spacing: 8) {
            Text("Get five dollars for every friend who joins!")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("Share Halo Fi with your friends and earn rewards together")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Referral Code Section

    private var referralCodeSection: some View {
        VStack(spacing: 16) {
            Text("Your Referral Code")
                .font(.headline)
                .foregroundColor(.gray)

            Text(referralCode)
                .font(.title.monospaced().bold())
                .foregroundColor(.white)
                .tracking(6)
                .accessibilityLabel("Referral code: \(referralCode.map { String($0) }.joined(separator: " "))")

            Button(action: {
                UIPasteboard.general.string = referralCode
                showingCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showingCopied = false
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: showingCopied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)
                    Text(showingCopied ? "Copied!" : "Copy Code")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    showingCopied
                        ? Color.green.opacity(0.3)
                        : Color.gray.opacity(0.2)
                )
                .cornerRadius(12)
            }
            .accessibilityLabel(showingCopied ? "Code copied" : "Copy referral code")
            .accessibilityHint("Double-tap to copy your referral code to clipboard")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(highContrast ? 0.15 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(highContrast ? 0.3 : 0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Button(action: { showingShareSheet = true }) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline)
                Text("Share with Friends")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [Color.indigo, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
        }
        .accessibilityLabel("Share Halo Fi with friends")
        .accessibilityHint("Double-tap to open the share menu")
    }

    // MARK: - How It Works Section

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How It Works")
                .font(.headline)
                .foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)

            howItWorksStep(number: "1", text: "Share your code or link with a friend")
            howItWorksStep(number: "2", text: "They sign up using your referral code")
            howItWorksStep(number: "3", text: "You both get five dollars credited to your account")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.gray.opacity(highContrast ? 0.15 : 0.08))
        .cornerRadius(16)
    }

    private func howItWorksStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(
                        colors: [Color.indigo, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .accessibilityHidden(true)

            Text(text)
                .font(.body)
                .foregroundColor(.gray)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}

// MARK: - Native Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    InviteFriendsView()
}
