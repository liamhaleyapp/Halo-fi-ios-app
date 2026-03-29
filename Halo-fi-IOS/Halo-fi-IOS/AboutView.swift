import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.haloHighContrast) private var highContrast

    @State private var showingTerms = false
    @State private var showingPrivacy = false
    @State private var showingHelp = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea(.all, edges: .all)

            VStack(spacing: 0) {
                headerView

                ScrollView {
                    VStack(spacing: 12) {
                        aboutSection
                        accessibilitySection
                        dataSecuritySection
                        legalSection
                        supportSection
                        appVersionSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }

                Spacer()
            }
        }
        .sheet(isPresented: $showingTerms) {
            LegalDocumentView(
                title: "Terms of Service",
                lastUpdated: "March 28, 2026",
                sections: termsOfServiceSections
            )
        }
        .sheet(isPresented: $showingPrivacy) {
            LegalDocumentView(
                title: "Privacy Policy",
                lastUpdated: "March 28, 2026",
                sections: privacyPolicySections
            )
        }
        .sheet(isPresented: $showingHelp) {
            HelpFeedbackView()
        }
    }

    // MARK: - Header View
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

            Text("About")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    // MARK: - About Section
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About Halo Fi")
                .font(.headline)
                .foregroundColor(.gray)

            Text("Halo Fi is a voice-first financial assistant built for people who are blind or have low vision. We believe everyone deserves clear, simple access to their finances — without needing to read a screen.")
                .font(.body)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Our mission is to bring visibility to personal finances through accessible and intelligent technology.")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(highContrast ? 0.25 : 0.1))
        .cornerRadius(16)
    }

    // MARK: - Accessibility Section
    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accessibility")
                .font(.headline)
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 12) {
                iconRow(icon: "mic.fill", color: .indigo, text: "Voice-first design — talk to Halo instead of tapping through menus")
                iconRow(icon: "eye.fill", color: .indigo, text: "Full VoiceOver support across every screen")
                iconRow(icon: "textformat.size", color: .indigo, text: "Dynamic Type — text scales with your system font size")
                iconRow(icon: "circle.lefthalf.filled", color: .indigo, text: "High contrast mode for low-vision users")
                iconRow(icon: "hand.raised.fill", color: .indigo, text: "Reduce motion support for motion-sensitive users")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.15), Color.purple.opacity(0.15)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Data Security Section
    private var dataSecuritySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Security")
                .font(.headline)
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 12) {
                iconRow(icon: "lock.shield.fill", color: .teal, text: "Bank-level AES-256 encryption for all your data")
                iconRow(icon: "building.columns.fill", color: .teal, text: "Bank connections powered by Plaid — we never see your login credentials")
                iconRow(icon: "eye.slash.fill", color: .teal, text: "We don't sell your data. Ever.")
                iconRow(icon: "waveform", color: .teal, text: "Voice conversations are processed in real-time and not stored beyond 90 days")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(highContrast ? 0.25 : 0.1))
        .cornerRadius(16)
    }

    // MARK: - Shared Icon Row
    private func iconRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.body)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Legal Section
    private var legalSection: some View {
        VStack(spacing: 8) {
            aboutLinkButton(icon: "doc.text.fill", title: "Terms of Service") {
                showingTerms = true
            }
            aboutLinkButton(icon: "hand.raised.fill", title: "Privacy Policy") {
                showingPrivacy = true
            }
        }
    }

    // MARK: - Support Section
    private var supportSection: some View {
        aboutLinkButton(icon: "questionmark.circle.fill", title: "Help & Feedback") {
            showingHelp = true
        }
    }

    // MARK: - Link Button
    private func aboutLinkButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.teal)
                    .font(.body)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.body)
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(highContrast ? .white : .gray)
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.gray.opacity(highContrast ? 0.25 : 0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(highContrast ? 0.3 : 0), lineWidth: 1)
            )
        }
        .accessibilityLabel(title)
        .accessibilityHint("Double-tap to open \(title)")
    }

    // MARK: - App Version
    private var appVersionSection: some View {
        HStack {
            Text("Halo Fi")
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(highContrast ? 0.25 : 0.1))
        .cornerRadius(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Halo Fi version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
    }
}

// MARK: - Legal Document View (reusable for Terms + Privacy)

struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let lastUpdated: String
    let sections: [LegalSection]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                        .font(.body)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Last updated: \(lastUpdated)")
                            .font(.caption)
                            .foregroundColor(.gray)

                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.heading)
                                    .font(.headline)
                                    .foregroundColor(.teal)

                                Text(section.body)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Text("© 2025-2026 Halo Fi, LLC. All rights reserved.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 60)
                }
            }
        }
    }
}

struct LegalSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
}

// MARK: - Help & Feedback View (combined support + bug report)

struct HelpFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var selectedType = "Question"
    @State private var showingSent = false

    let feedbackTypes = ["Question", "Bug Report", "Feature Request", "Accessibility Issue", "Other"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("Help & Feedback")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Done") { dismiss() }
                        .foregroundColor(.blue)
                        .font(.body)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView {
                    VStack(spacing: 20) {
                        // Type selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What can we help with?")
                                .font(.body)
                                .foregroundColor(.white)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(feedbackTypes, id: \.self) { type in
                                        Button(action: { selectedType = type }) {
                                            Text(type)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(selectedType == type ? .white : .gray)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(
                                                    selectedType == type ?
                                                        AnyShapeStyle(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing)) :
                                                        AnyShapeStyle(Color.gray.opacity(0.15))
                                                )
                                                .cornerRadius(20)
                                        }
                                        .accessibilityLabel(type)
                                        .accessibilityValue(selectedType == type ? "Selected" : "Not selected")
                                        .accessibilityAddTraits(selectedType == type ? [.isSelected] : [])
                                    }
                                }
                            }
                        }

                        // Message input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your message")
                                .font(.body)
                                .foregroundColor(.white)

                            TextField("Tell us what's on your mind...", text: $message, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(5...10)
                                .accessibilityLabel("Feedback message")
                                .accessibilityHint("Describe your question, issue, or feedback")
                        }

                        // Submit
                        Button(action: { showingSent = true }) {
                            Text("Send")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(colors: [Color.teal, Color.blue], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(16)
                        }
                        .disabled(message.isEmpty)
                        .opacity(message.isEmpty ? 0.6 : 1.0)
                        .accessibilityLabel("Send feedback")
                        .accessibilityHint(message.isEmpty ? "Type a message first" : "Double-tap to send your \(selectedType.lowercased())")

                        // Contact info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You can also reach us at:")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("support@halofiapp.com")
                                .font(.caption)
                                .foregroundColor(.teal)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .alert("Sent!", isPresented: $showingSent) {
            Button("OK") {
                message = ""
                dismiss()
            }
        } message: {
            Text("Thanks for your \(selectedType.lowercased()). We'll get back to you within 24 hours.")
        }
    }
}

// MARK: - Terms of Service Content

let termsOfServiceSections: [LegalSection] = [
    LegalSection(heading: "Acceptance of Terms", body: "These Terms of Service constitute a legally binding contract between you and Halo Fi, LLC, a Florida limited liability company. By downloading, installing, creating an account, accessing, or using the Halo Fi mobile application or any related services, you agree to be bound by these Terms and our Privacy Policy.\n\nIf you do not agree to these Terms, you must immediately discontinue all use and uninstall the application."),
    LegalSection(heading: "Service Description", body: "Halo Fi provides a voice-first financial assistant platform designed primarily for accessibility, enabling users — particularly those who are visually impaired — to securely access financial information and receive automated insights through natural language voice commands.\n\nThe Services are an assistive technology tool and are not a substitute for professional financial services or human assistance."),
    LegalSection(heading: "Not Financial Advice", body: "All information provided through the Services is for general informational purposes only and does not constitute financial, investment, tax, legal, or any other form of professional advice. Halo Fi is not a bank, financial advisor, broker-dealer, or financial institution of any kind.\n\nYou should consult with qualified professionals before making any financial decisions. We expressly disclaim all liability for any financial losses resulting from your reliance on information provided through the Services."),
    LegalSection(heading: "Financial Account Connections", body: "Halo Fi uses Plaid Technologies, Inc. to securely access your financial account information. We never receive, store, or have access to your banking username, password, or login credentials.\n\nFinancial data displayed in the app may be delayed, incomplete, or inaccurate due to factors outside our control. You should always verify financial information directly with your financial institution."),
    LegalSection(heading: "Voice Processing & AI", body: "When you use voice features, your commands are recorded, transcribed, and processed using AI systems including OpenAI. De-identified transcripts may be shared with AI providers — no personal identifiers or account numbers are included.\n\nAI-generated responses may contain errors and should not be relied upon as the sole basis for any financial decision."),
    LegalSection(heading: "Subscriptions & Payments", body: "Subscription fees are processed through Apple's In-App Purchase system. Subscriptions automatically renew unless cancelled before the renewal date. Fees are generally non-refundable except as required by law.\n\nWe reserve the right to change subscription pricing with at least 30 days' notice to existing subscribers."),
    LegalSection(heading: "Accessibility Disclaimer", body: "While we design our Services with accessibility as a priority, we do not warrant that the Services will be fully accessible to all users in all circumstances. Voice recognition may be affected by accents, background noise, or other factors.\n\nThe Services are a supplementary tool and are not intended to replace professional accessibility services, screen readers, or human assistance."),
    LegalSection(heading: "Limitation of Liability", body: "To the maximum extent permitted by law, Halo Fi's total aggregate liability for all claims shall not exceed the greater of the amount you paid us in the 12 months preceding the claim or $100.\n\nWe are not liable for any indirect, incidental, special, consequential, or punitive damages, including financial losses of any kind."),
    LegalSection(heading: "Dispute Resolution", body: "All disputes will be resolved through binding individual arbitration administered by the American Arbitration Association, rather than in court. You waive the right to a jury trial and to participate in class actions.\n\nYou may opt out of arbitration within 30 days of accepting these Terms by emailing legal@halofi.com."),
    LegalSection(heading: "Governing Law", body: "These Terms are governed by the laws of the State of Florida. For disputes not subject to arbitration, you consent to the exclusive jurisdiction of courts in Miami-Dade County, Florida."),
    LegalSection(heading: "Contact", body: "Legal inquiries: legal@halofi.com\nPrivacy inquiries: privacy@halofi.com\nGeneral support: support@halofiapp.com\nWebsite: halofiapp.com"),
]

// MARK: - Privacy Policy Content

let privacyPolicySections: [LegalSection] = [
    LegalSection(heading: "Overview", body: "Halo Fi, LLC is a Florida limited liability company that provides voice-first financial assistant technology designed for accessibility. This Privacy Policy describes our practices regarding the collection, use, storage, sharing, and protection of your personal information."),
    LegalSection(heading: "Information We Collect", body: "Account registration: name, email, phone number, date of birth, and encrypted authentication credentials.\n\nVoice data: recordings of your commands, speech-to-text transcriptions, and derived metadata.\n\nFinancial information (via Plaid): bank names, account types, balances, transaction history, and investment holdings. We never receive your banking login credentials.\n\nDevice information: anonymized device identifiers, OS version, app version, and approximate location (city level only)."),
    LegalSection(heading: "How We Use Your Information", body: "We use your information to provide account balances, transaction history, and financial insights; process voice commands; generate personalized summaries; customize accessibility settings; deliver security notifications; and comply with legal obligations.\n\nWe also use anonymized and aggregated data to improve our services and accessibility features."),
    LegalSection(heading: "We Don't Sell Your Data", body: "Halo Fi does not sell, rent, lease, or trade your personal information to third parties for their marketing purposes. We have not sold personal information in the preceding 12 months and have no plans to do so."),
    LegalSection(heading: "Service Providers", body: "We share data with trusted service providers:\n\n• Plaid — financial data aggregation\n• AWS — cloud infrastructure\n• OpenAI — natural language processing (de-identified transcripts only)\n• Apple — iOS platform and App Store\n• Twilio — SMS verification\n• Firebase — anonymized analytics\n\nAll providers are contractually required to protect your information."),
    LegalSection(heading: "Data Security", body: "All data in transit is encrypted with TLS 1.3. All data at rest is encrypted with AES-256. Voice data is end-to-end encrypted during transmission. Financial data tokens use bank-grade encryption.\n\nWe implement multi-factor authentication, role-based access controls, regular penetration testing, and automated security monitoring."),
    LegalSection(heading: "Data Retention", body: "Account information: duration of account plus 7 years after closure.\nFinancial information: 7 years from transaction date.\nVoice recordings and transcripts: automatically deleted after 90 days.\nUsage analytics: personally identifiable data deleted after 1 year.\nSupport communications: 3 years after resolution.\n\nUpon account deletion, personal data is removed from active systems within 30 days and from backups within 90 days."),
    LegalSection(heading: "Your Rights", body: "You have the right to access, correct, delete, and obtain a portable copy of your personal information. You can opt out of marketing communications and withdraw consent at any time.\n\nTo exercise your rights, email privacy@halofi.com. We will respond within 30 days."),
    LegalSection(heading: "SMS & Phone Verification", body: "We use Twilio for SMS verification during sign-up and login. You consent to receive one-time verification codes and security alerts. Message frequency is typically 1-3 messages per authentication event. Message and data rates may apply.\n\nWe never use your phone number for marketing. Opt out by replying STOP to any verification message."),
    LegalSection(heading: "Children's Privacy", body: "Halo Fi is not intended for anyone under 18. We do not knowingly collect information from children. If we discover we have collected data from a child under 18, we will delete it promptly."),
    LegalSection(heading: "Changes to This Policy", body: "For material changes, we provide at least 30 days advance notice via email and in-app notification. Your continued use after changes constitutes acceptance."),
    LegalSection(heading: "Contact", body: "Privacy inquiries: privacy@halofi.com\nGeneral support: support@halofiapp.com\nWebsite: halofiapp.com\n\nWe acknowledge requests within 5 business days and fulfill most requests within 30 days."),
]

#Preview {
    AboutView()
}
