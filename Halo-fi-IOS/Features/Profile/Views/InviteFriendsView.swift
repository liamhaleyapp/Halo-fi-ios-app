//
//  InviteFriendsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//  Phase 1 (attribution-only): real per-user code from backend, no
//  premature reward promise. Discount delivery lands in Phase 2 once
//  Apple Offer Codes are wired in.
//

import SwiftUI
import UIKit

struct InviteFriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.haloHighContrast) private var highContrast

    @State private var showingCopied = false
    @State private var showingShareSheet = false

    @State private var referralCode: String?
    @State private var invitedCount: Int = 0
    @State private var loading = true
    @State private var loadError: String?

    private let networkService = NetworkService.shared

    /// Web landing page that intercepts the link and routes the visitor
    /// to the App Store. We use a server-rendered page (not a universal
    /// link / deep link into the app yet) per Phase 1 plan — universal
    /// link setup can land post-launch without breaking shared codes.
    private func referralLink(for code: String) -> String {
        "https://halofi.app/ref/\(code)"
    }

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
        .task {
            await loadStats()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let code = referralCode {
                ShareSheet(items: [
                    "Join me on HaloFi \u{2014} your voice-first financial assistant! Use my code \(code) to get started: \(referralLink(for: code))"
                ])
            }
        }
    }

    // MARK: - Networking

    private struct StatsResponse: Decodable {
        let referral_code: String?
        let invited_count: Int
        let pending_rewards: Int
    }

    private func loadStats() async {
        loading = true
        loadError = nil
        do {
            let response: StatsResponse = try await networkService.authenticatedRequest(
                endpoint: "/referrals/stats",
                method: .GET,
                body: nil,
                responseType: StatsResponse.self
            )
            referralCode = response.referral_code
            invitedCount = response.invited_count
        } catch {
            loadError = "Couldn't load your code. Pull down to retry."
            Logger.error("InviteFriendsView: failed to load stats — \(error)")
        }
        loading = false
    }

    // MARK: - Incentive Section

    private var incentiveSection: some View {
        VStack(spacing: 8) {
            Text("Invite friends to HaloFi")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            // Phase 1 copy: no specific reward promise. Phase 2 will swap
            // this in for "Get $X for every friend who joins" once the
            // Apple Offer Code pipeline is live.
            Text("Share Halo Fi with people who'd benefit. Discounts launching soon.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            if invitedCount > 0 {
                Text("\(invitedCount) friend\(invitedCount == 1 ? "" : "s") joined so far")
                    .font(.footnote)
                    .foregroundColor(.green)
                    .padding(.top, 4)
                    .accessibilityLabel("\(invitedCount) friends have joined using your code")
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Referral Code Section

    private var referralCodeSection: some View {
        VStack(spacing: 16) {
            Text("Your Referral Code")
                .font(.headline)
                .foregroundColor(.gray)

            if let code = referralCode {
                Text(code)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(2)
                    .accessibilityLabel("Referral code: \(code.map { String($0) }.joined(separator: " "))")

                Button(action: {
                    UIPasteboard.general.string = code
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
            } else if loading {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Loading your referral code")
            } else if let loadError {
                Text(loadError)
                    .font(.subheadline)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await loadStats() }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
            }
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
        .disabled(referralCode == nil)
        .opacity(referralCode == nil ? 0.5 : 1.0)
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
            howItWorksStep(number: "2", text: "They sign up and enter your code")
            // Phase 1: no specific reward. Phase 2 swaps step 3 in
            // for "You both get $X off your subscription".
            howItWorksStep(number: "3", text: "We track every successful signup. Rewards launching soon.")
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
