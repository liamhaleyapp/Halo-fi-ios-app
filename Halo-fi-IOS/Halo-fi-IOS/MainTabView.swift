import SwiftUI

struct MainTabView: View {
    @StateObject private var userManager = UserManager()
    @State private var selectedTab = 0
    
    var body: some View {
        Group {
            if userManager.isAuthenticated {
                TabView {
                    HomeView()
                        .tabItem {
                            Image(systemName: "mic.circle.fill")
                            Text("Agent")
                        }
                        .tag(0)
                        .accessibilityLabel("Voice Agent")
                        .accessibilityHint("Talk to Halo about your finances")

                    AccountsOverviewView()
                        .tabItem {
                            Image(systemName: "creditcard.fill")
                            Text("Account")
                        }
                        .tag(1)
                        .accessibilityLabel("Accounts Overview")
                        .accessibilityHint("View your linked bank accounts")

                    SettingsView()
                        .tabItem {
                            Image(systemName: "gearshape.fill")
                            Text("Settings")
                        }
                        .tag(2)
                        .accessibilityLabel("Settings")
                        .accessibilityHint("Manage your profile and preferences")
                }
                .accentColor(.blue)
                .preferredColorScheme(.dark)
            } else {
                OnboardingView()
            }
        }
        .userManager(userManager)
    }
}

#Preview {
    MainTabView()
} 