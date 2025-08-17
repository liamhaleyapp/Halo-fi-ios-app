import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State Variables
    @State private var showingTeam = false
    @State private var showingTerms = false
    @State private var showingPrivacy = false
    @State private var showingContactSupport = false
    @State private var showingBugReport = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    headerView
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            whatIsHaloFiSection
                            ourMissionSection
                            meetTheTeamButtonSection
                            dataSecuritySection
                            legalAndSupportSection
                            appVersionSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingTeam) {
            TeamView()
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
            
            Spacer()
            
            Text("About")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
            
            // Invisible spacer to center the title
            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 15)
        .padding(.bottom, 20)
    }
    
    // MARK: - What is Halo Fi Section
    private var whatIsHaloFiSection: some View {
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Our Mission Section
    private var ourMissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Our Mission")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("To bring visibility to personal finances through accessible and intelligent technology—empowering everyone, especially those with visual impairments.")
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Meet the Team Button Section
    private var meetTheTeamButtonSection: some View {
        Button(action: {
            showingTeam = true
        }) {
            HStack {
                Text("Meet the Team")
                    .font(.body)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
            .cornerRadius(16)
        }
    }
    
    // MARK: - Data Security Section
    private var dataSecuritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Security")
                .font(.headline)
                .foregroundColor(.gray)
            
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.teal)
                    .font(.title3)
                
                Text("End-to-end encryption")
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Legal and Support Section
    private var legalAndSupportSection: some View {
        VStack(spacing: 16) {
            // Legal Links
            VStack(spacing: 12) {
                Button(action: {
                    showingTerms = true
                }) {
                    HStack {
                        Text("Terms of Service")
                            .font(.body)
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
                }
                
                Button(action: {
                    showingPrivacy = true
                }) {
                    HStack {
                        Text("Privacy Policy")
                            .font(.body)
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
                }
            }
            
            // Support & Feedback
            VStack(spacing: 12) {
                Button(action: {
                    showingContactSupport = true
                }) {
                    HStack {
                        Text("Contact Support")
                            .font(.body)
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
                }
                
                Button(action: {
                    showingBugReport = true
                }) {
                    HStack {
                        Text("Report a Bug / Feedback")
                        .font(.body)
                        .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
                }
            }
        }
    }
    
    // MARK: - App Version Section
    private var appVersionSection: some View {
        VStack(spacing: 16) {
            // App Version
            HStack {
                Text("App Version: v1.0.0")
                    .font(.body)
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
        }
    }
}

// MARK: - Team View (Modal)
struct TeamView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with Done button
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.body)
                    .padding(.trailing, 20)
                    .padding(.top, 10)
                }
                
                // Title
                Text("Meet the Team")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                
                // Content
                ScrollView {
                    VStack(spacing: 20) {
                            // Andrew Babin
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Andrew Babin")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text("Co-Founder")
                                    .font(.headline)
                                    .foregroundColor(.teal)
                                
                                Text("Diagnosed with Stargardt's disease at a young age, Andrew has never let vision loss define him. He embraced technology as a way to adapt and thrive, building a career in finance over the past five years. Passionate about AI, he explores how it can support daily life and create meaningful impact.")
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                            
                            // Liam Haley
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Liam Haley")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text("Co-Founder")
                                    .font(.headline)
                                    .foregroundColor(.teal)
                                
                                Text("Liam is an AI developer and previous fintech startup founder. His 15-year friendship with Andrew gave him deep perspective on the challenges of vision loss. While not visually impaired himself, he brings technical expertise and startup experience to the mission of Halo Fi.")
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                            
                            // Together Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Together")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Text("Andrew and Liam combined their professional skills and life experiences to create Halo Fi—a voice-first financial assistant designed to bring clarity and accessibility to personal finance. Their vision is simple: build a tool that has no downside, only benefits, and can help hundreds of thousands gain clearer access to their finances.")
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(16)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Terms View (Modal)
struct TermsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with Done button
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
                        
                        Text("Last updated: December 2024")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("By using Halo Fi, you agree to these terms...")
                            .font(.body)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                        
                        // Add more terms content here
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
                // Header with Done button
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
                        
                        Text("Last updated: December 2024")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("Your privacy is important to us. This policy describes how we collect, use, and protect your information...")
                            .font(.body)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                        
                        // Add more privacy content here
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
                // Header with Done button
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
                // Header with Done button
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
                    Text("Report a Bug / Feedback")
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
