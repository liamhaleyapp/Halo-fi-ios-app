//
//  AboutView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//  Redesigned with Accessibility, Security, and legal content.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.haloHighContrast) private var highContrast

    @State private var showingTerms = false
    @State private var showingPrivacy = false
    @State private var showingHelpFeedback = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WhatIsHaloFiSection()
                OurMissionSection()
                AccessibilityFeaturesSection()
                DataSecuritySection()
                LegalSection(
                    onTermsTap: { showingTerms = true },
                    onPrivacyTap: { showingPrivacy = true }
                )
                SupportSection(
                    onHelpTap: { showingHelpFeedback = true }
                )
                AppVersionSection()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingTerms) {
            LegalDocumentView(
                title: "Terms of Service",
                sections: Self.termsOfServiceSections,
                endpoint: APIEndpoints.Legal.terms
            )
        }
        .sheet(isPresented: $showingPrivacy) {
            LegalDocumentView(
                title: "Privacy Policy",
                sections: Self.privacyPolicySections,
                endpoint: APIEndpoints.Legal.privacy
            )
        }
        .sheet(isPresented: $showingHelpFeedback) {
            HelpFeedbackView()
        }
    }

    // MARK: - Legal Content

    static let termsOfServiceSections: [LegalSectionContent] = [
        LegalSectionContent(
            heading: "1. Acceptance of Terms",
            body: "By downloading, accessing, or using HaloFi, you agree to be bound by these Terms of Service. If you do not agree, do not use the app."
        ),
        LegalSectionContent(
            heading: "2. Description of Service",
            body: "HaloFi is a voice-first personal financial assistant that helps users view account balances, track spending, and manage budgets. HaloFi connects to your financial institutions via Plaid to retrieve account data."
        ),
        LegalSectionContent(
            heading: "3. User Accounts",
            body: "You must provide accurate information when creating an account. You are responsible for maintaining the security of your login credentials. You must be at least 18 years old to use HaloFi."
        ),
        LegalSectionContent(
            heading: "4. Financial Data",
            body: "HaloFi displays financial data from your linked accounts but does not provide financial advice. All data is read-only \u{2014} HaloFi cannot move money, make payments, or execute transactions on your behalf."
        ),
        LegalSectionContent(
            heading: "5. Privacy",
            body: "Your use of HaloFi is also governed by our Privacy Policy. We take your data security seriously and use industry-standard encryption."
        ),
        LegalSectionContent(
            heading: "6. Limitation of Liability",
            body: "HaloFi is provided \"as is\" without warranties. We are not liable for any financial decisions made based on information displayed in the app."
        ),
    ]

    static let privacyPolicySections: [LegalSectionContent] = [
        LegalSectionContent(
            heading: "Information We Collect",
            body: "Account information (name, email, phone), financial data from linked institutions via Plaid (balances, transactions), and app usage data for improving the service."
        ),
        LegalSectionContent(
            heading: "How We Use Your Information",
            body: "To provide and improve the HaloFi service, display your financial data, generate spending insights, and communicate important updates about your account."
        ),
        LegalSectionContent(
            heading: "Data Security",
            body: "All financial data is encrypted in transit and at rest using AES-256 encryption. Plaid access tokens are encrypted with Fernet encryption. We never store your bank login credentials."
        ),
        LegalSectionContent(
            heading: "Third-Party Services",
            body: "We use Plaid for bank connectivity, Supabase for authentication and data storage, and ElevenLabs for voice services. Each service has its own privacy policy."
        ),
        LegalSectionContent(
            heading: "Your Rights",
            body: "You can request deletion of your account and all associated data at any time through the Settings menu. Upon deletion, all financial data, linked accounts, and personal information are permanently removed."
        ),
        LegalSectionContent(
            heading: "Contact",
            body: "For privacy-related questions, contact us at privacy@halofiapp.com."
        ),
    ]
}

// MARK: - Legal Document Model

struct LegalSectionContent: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
}

// MARK: - Remote Legal Response

private struct LegalResponse: Codable {
    let title: String
    let last_updated: String
    let sections: [LegalSectionResponse]
}

private struct LegalSectionResponse: Codable {
    let heading: String
    let body: String
}

// MARK: - Legal Document View

struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let fallbackSections: [LegalSectionContent]
    let endpoint: String

    @State private var sections: [LegalSectionContent] = []
    @State private var lastUpdated: String = ""
    @State private var isLoading = true

    init(title: String, sections: [LegalSectionContent], endpoint: String = "") {
        self.title = title
        self.fallbackSections = sections
        self.endpoint = endpoint
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !lastUpdated.isEmpty {
                        Text("Last updated: \(lastUpdated)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.heading)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(section.body)
                                    .font(.body)
                                    .foregroundColor(.gray)
                                    .lineLimit(nil)
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close \(title)")
                }
            }
            .task {
                await fetchLegalContent()
            }
        }
    }

    private func fetchLegalContent() async {
        guard !endpoint.isEmpty else {
            sections = fallbackSections
            isLoading = false
            return
        }

        do {
            let url = URL(string: APIEndpoints.baseURL + endpoint)!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(LegalResponse.self, from: data)
            sections = response.sections.map {
                LegalSectionContent(heading: $0.heading, body: $0.body)
            }
            lastUpdated = response.last_updated
        } catch {
            sections = fallbackSections
        }
        isLoading = false
    }
}

// MARK: - Help & Feedback View

struct HelpFeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpRow(
                        icon: "envelope.fill",
                        color: .blue,
                        title: "Email Support",
                        detail: "support@halofiapp.com",
                        hint: "Send an email to our support team"
                    )
                    helpRow(
                        icon: "ant.fill",
                        color: .orange,
                        title: "Report a Bug",
                        detail: "bugs@halofiapp.com",
                        hint: "Report a bug or issue with the app"
                    )
                    helpRow(
                        icon: "lightbulb.fill",
                        color: .yellow,
                        title: "Feature Request",
                        detail: "feedback@halofiapp.com",
                        hint: "Suggest a new feature or improvement"
                    )
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Help & Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close Help & Feedback")
                }
            }
        }
    }

    private func helpRow(icon: String, color: Color, title: String, detail: String, hint: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityHint(hint)
    }
}

#Preview {
    AboutView()
}
