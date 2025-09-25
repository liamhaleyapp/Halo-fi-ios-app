import SwiftUI

struct OnboardingView: View {
    @Environment(\.userManager) private var userManager
    @State private var currentPage = 0
    @State private var showingSignUp = false
    @State private var showingSignIn = false
    
    private let onboardingPages = [
        OnboardingPage(
            title: "Welcome to Halo Fi",
            subtitle: "Your voice-first financial assistant",
            description: "Get personalized financial guidance through natural conversations. No more complex menus or confusing interfaces.",
            icon: "HaloFiLogo",
            color: [Color.purple, Color.indigo]
        ),
        OnboardingPage(
            title: "Smart Financial Insights",
            subtitle: "Powered by AI & Plaid",
            description: "Connect your accounts securely and get real-time insights about your spending, saving, and financial health.",
            icon: "HaloFiLogo",
            color: [Color.blue, Color.teal]
        ),
        OnboardingPage(
            title: "Accessible for Everyone",
            subtitle: "Built with inclusivity in mind",
            description: "Designed specifically for the visually impaired community, with voice-first navigation and high-contrast interfaces.",
            icon: "HaloFiLogo",
            color: [Color.orange, Color.red]
        )
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Page Content
                    TabView(selection: $currentPage) {
                        ForEach(0..<onboardingPages.count, id: \.self) { index in
                            pageView(for: onboardingPages[index], geometry: geometry)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentPage)
                    
                    // Bottom Section
                    bottomSection
                        .padding(.bottom, geometry.safeAreaInsets.bottom)
                }
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingSignUp) {
            SignUpView()
        }
        .fullScreenCover(isPresented: $showingSignIn) {
            SignInView()
        }
    }
    
    // MARK: - Page View
    private func pageView(for page: OnboardingPage, geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: geometry.size.height * 0.15)
            
            // Logo with gradient background
            ZStack {
                // Gradient background circle
                Circle()
                    .fill(LinearGradient(colors: page.color, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: min(120, geometry.size.width * 0.25), height: min(120, geometry.size.width * 0.25))
                
                // Your custom logo
                Image(page.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: min(80, geometry.size.width * 0.2), height: min(80, geometry.size.width * 0.2))
            }
            
            // Text Content
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 32)
            
            Spacer()
                .frame(height: geometry.size.height * 0.15)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Bottom Section
    private var bottomSection: some View {
        VStack(spacing: 24) {
            // Page Indicators
            HStack(spacing: 8) {
                ForEach(0..<onboardingPages.count, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.white : Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentPage)
                }
            }
            
            // Action Buttons
            VStack(spacing: 16) {
                // Get Started Button
                Button(action: {
                    showingSignUp = true
                }) {
                    Text("Get Started")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(16)
                }
                
                // Sign In Button
                Button(action: {
                    showingSignIn = true
                }) {
                    Text("I already have an account")
                        .font(.body)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Onboarding Page Model
struct OnboardingPage {
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let color: [Color]
}

#Preview {
    OnboardingView()
}
