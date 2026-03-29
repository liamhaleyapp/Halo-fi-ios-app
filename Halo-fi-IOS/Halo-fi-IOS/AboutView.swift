import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.haloHighContrast) private var highContrast

    @State private var showingTerms = false
    @State private var showingPrivacy = false
    @State private var showingContactSupport = false
    @State private var showingBugReport = false

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
            TermsView()
        }
        .sheet(isPresented: $showingPrivacy) {
            PrivacyView()
        }
        .sheet(isPresented: $showingContactSupport) {
            ContactSupportView()
        }
        .sheet(isPresented: $showingBugReport) {
            BugReportView()
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            Button(action: {
                dismiss()
            }) {
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

            Color.clear
                .frame(width: 40, height: 40)
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
                accessibilityRow(icon: "mic.fill", text: "Voice-first design — talk to Halo instead of tapping through menus")
                accessibilityRow(icon: "eye.fill", text: "Full VoiceOver support across every screen")
                accessibilityRow(icon: "textformat.size", text: "Dynamic Type — text scales with your system font size")
                accessibilityRow(icon: "circle.lefthalf.filled", text: "High contrast mode for low-vision users")
                accessibilityRow(icon: "hand.raised.fill", text: "Reduce motion support for motion-sensitive users")
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

    private func accessibilityRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.indigo)
                .font(.body)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Data Security Section
    private var dataSecuritySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Security")
                .font(.headline)
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 12) {
                securityRow(icon: "lock.shield.fill", text: "Bank-level encryption for all your data")
                securityRow(icon: "building.columns.fill", text: "Bank connections powered by Plaid — we never see your login credentials")
                securityRow(icon: "eye.slash.fill", text: "We don't sell your data. Ever.")
                securityRow(icon: "server.rack", text: "Voice conversations are processed in real-time and not stored")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(highContrast ? 0.25 : 0.1))
        .cornerRadius(16)
    }

    private func securityRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.teal)
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
        VStack(spacing: 8) {
            aboutLinkButton(icon: "envelope.fill", title: "Contact Support") {
                showingContactSupport = true
            }
            aboutLinkButton(icon: "ladybug.fill", title: "Report a Bug") {
                showingBugReport = true
            }
        }
    }

    // MARK: - Link Button Component
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

    // MARK: - App Version Section
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

// MARK: - Terms View (Modal)
struct TermsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.body)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Terms of Service")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.top, 8)

                        Text("Last updated: March 2026")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Text("By using Halo Fi, you agree to these terms of service. Halo Fi provides voice-based financial insights and account aggregation through third-party services. We are not a bank, financial advisor, or licensed financial institution.\n\nHalo Fi uses Plaid to connect to your financial accounts. By linking your accounts, you authorize Plaid to access your financial data on your behalf.\n\nAll financial information provided through Halo Fi is for informational purposes only and should not be considered financial advice. Always consult a qualified professional for financial decisions.\n\nWe reserve the right to modify these terms at any time. Continued use of the app after changes constitutes acceptance of the updated terms.")
                            .font(.body)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Privacy View (Modal)
struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.body)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Privacy Policy")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.top, 8)

                        Text("Last updated: March 2026")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Group {
                            Text("What We Collect")
                                .font(.headline)
                                .foregroundColor(.teal)

                            Text("When you create an account, we collect your name, email, and phone number. When you link bank accounts through Plaid, we receive account balances, transaction history, and account metadata. We use this data solely to provide you with personalized financial insights.")
                                .font(.body)
                                .foregroundColor(.white)

                            Text("What We Don't Do")
                                .font(.headline)
                                .foregroundColor(.teal)

                            Text("We never see your bank login credentials — Plaid handles that securely. We don't sell, share, or rent your personal or financial data to third parties. Voice conversations are processed in real-time for responses and are not recorded or stored.")
                                .font(.body)
                                .foregroundColor(.white)

                            Text("How We Protect Your Data")
                                .font(.headline)
                                .foregroundColor(.teal)

                            Text("All data is encrypted in transit and at rest. Access tokens for bank connections are encrypted with industry-standard encryption. We use secure cloud infrastructure with regular security audits.")
                                .font(.body)
                                .foregroundColor(.white)

                            Text("Your Rights")
                                .font(.headline)
                                .foregroundColor(.teal)

                            Text("You can disconnect your bank accounts at any time. You can request deletion of your account and all associated data by contacting support. We will process deletion requests within 30 days.")
                                .font(.body)
                                .foregroundColor(.white)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Contact Support View (Modal)
struct ContactSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var showingSent = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.body)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .padding(.top, 8)

                VStack(spacing: 20) {
                    Text("Contact Support")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("How can we help you?")
                            .font(.body)
                            .foregroundColor(.white)

                        TextField("Your message...", text: $message, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(4...8)
                            .accessibilityLabel("Support message")
                            .accessibilityHint("Type your message to the support team")
                    }
                    .padding(.horizontal, 20)

                    Button(action: {
                        showingSent = true
                    }) {
                        Text("Send Message")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(LinearGradient(colors: [Color.teal, Color.blue], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 20)
                    .disabled(message.isEmpty)
                    .opacity(message.isEmpty ? 0.6 : 1.0)
                    .accessibilityLabel("Send message")
                    .accessibilityHint(message.isEmpty ? "Type a message first" : "Double-tap to send your message")

                    Spacer()
                }

                Spacer()
            }
        }
        .alert("Message Sent!", isPresented: $showingSent) {
            Button("OK") { }
        } message: {
            Text("We'll get back to you within 24 hours.")
        }
    }
}

// MARK: - Bug Report View (Modal)
struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bugDescription = ""
    @State private var showingSent = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.body)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .padding(.top, 8)

                VStack(spacing: 20) {
                    Text("Report a Bug")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Help us improve Halo Fi")
                            .font(.body)
                            .foregroundColor(.white)

                        TextField("Describe the issue or share your feedback...", text: $bugDescription, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(4...8)
                            .accessibilityLabel("Bug report or feedback")
                            .accessibilityHint("Describe the issue or share your feedback")
                    }
                    .padding(.horizontal, 20)

                    Button(action: {
                        showingSent = true
                    }) {
                        Text("Submit Report")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(LinearGradient(colors: [Color.teal, Color.blue], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 20)
                    .disabled(bugDescription.isEmpty)
                    .opacity(bugDescription.isEmpty ? 0.6 : 1.0)
                    .accessibilityLabel("Submit report")
                    .accessibilityHint(bugDescription.isEmpty ? "Describe the issue first" : "Double-tap to submit your report")

                    Spacer()
                }

                Spacer()
            }
        }
        .alert("Report Submitted!", isPresented: $showingSent) {
            Button("OK") { }
        } message: {
            Text("Thank you for helping us improve Halo Fi!")
        }
    }
}

#Preview {
    AboutView()
}
