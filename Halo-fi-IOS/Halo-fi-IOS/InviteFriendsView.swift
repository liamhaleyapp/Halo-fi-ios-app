import SwiftUI

struct InviteFriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.haloHighContrast) private var highContrast

    @State private var showingCopiedLink = false
    @State private var showingShareSheet = false

    // TODO: Pull from user's actual referral code in UserManager
    private let referralCode = "HALO123"
    private let referralLink = "https://halofi.app/ref/user123"

    private var shareMessage: String {
        "Check out Halo Fi — a voice-first financial assistant built for accessibility. Use my referral code \(referralCode) to get started: \(referralLink)"
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    headerView

                    ScrollView {
                        VStack(spacing: 16) {
                            incentiveSection
                            shareButtonSection
                            referralCodeSection
                            howItWorksSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }

                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .alert("Copied!", isPresented: $showingCopiedLink) {
            Button("OK") { }
        } message: {
            Text("Your referral code has been copied to the clipboard.")
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [shareMessage])
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Go back")

            Spacer()

            Text("Invite Friends")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 15)
        .padding(.bottom, 20)
    }

    // MARK: - Incentive
    private var incentiveSection: some View {
        VStack(spacing: 8) {
            Text("Share Halo Fi")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Help others take control of their finances through voice. Share Halo Fi with friends and family who could benefit.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Share Button
    private var shareButtonSection: some View {
        Button(action: { showingShareSheet = true }) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundColor(.white)

                Text("Share Halo Fi")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(highContrast ? 0.5 : 0), lineWidth: 1)
            )
        }
        .accessibilityLabel("Share Halo Fi")
        .accessibilityHint("Double-tap to open share options — send via message, email, or other apps")
    }

    // MARK: - Referral Code
    private var referralCodeSection: some View {
        VStack(spacing: 12) {
            Text("Your Referral Code")
                .font(.headline)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text(referralCode)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .kerning(2)

                Spacer()

                Button(action: {
                    UIPasteboard.general.string = referralCode
                    showingCopiedLink = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.subheadline)
                        Text("Copy")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.25))
                    .cornerRadius(10)
                }
                .accessibilityLabel("Copy referral code \(referralCode)")
                .accessibilityHint("Double-tap to copy to clipboard")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.purple.opacity(0.15), Color.indigo.opacity(0.15)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - How It Works
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How It Works")
                .font(.headline)
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 12) {
                stepRow(number: "1", text: "Share your link or code with a friend")
                stepRow(number: "2", text: "They sign up using your referral code")
                stepRow(number: "3", text: "You both get rewarded")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(highContrast ? 0.25 : 0.1))
        .cornerRadius(16)
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }
}

// MARK: - iOS Share Sheet

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
