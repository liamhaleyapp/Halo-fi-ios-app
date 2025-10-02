import SwiftUI

struct MainTabView: View {
    @StateObject private var userManager = UserManager()
    @State private var selectedTab = 0
    
    var body: some View {
        Group {
            if userManager.isAuthenticated {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad-specific layout with sidebar navigation
                    NavigationSplitView {
                        SidebarView(selectedTab: $selectedTab)
                    } detail: {
                        DetailView(selectedTab: selectedTab)
                    }
                    .accentColor(.blue)
                    .preferredColorScheme(.dark)
                } else {
                    // iPhone layout with tab bar
                    TabView(selection: $selectedTab) {
                        HomeView()
                            .tabItem {
                                Image(systemName: "mic.circle.fill")
                                Text("Agent")
                            }
                            .tag(0)
                        
                        AccountsOverviewView()
                            .tabItem {
                                Image(systemName: "creditcard.fill")
                                Text("Account")
                            }
                            .tag(1)
                        
                        SettingsView()
                            .tabItem {
                                Image(systemName: "gearshape.fill")
                                Text("Settings")
                            }
                            .tag(2)
                    }
                    .accentColor(.blue)
                    .preferredColorScheme(.dark)
                }
            } else {
                OnboardingView()
            }
        }
        .userManager(userManager)
    }
}

// MARK: - iPad Sidebar Navigation
struct SidebarView: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        List {
            Button(action: { selectedTab = 0 }) {
                HStack {
                    Image(systemName: "mic.circle.fill")
                        .foregroundColor(selectedTab == 0 ? .blue : .primary)
                    Text("Agent")
                        .foregroundColor(selectedTab == 0 ? .blue : .primary)
                    Spacer()
                }
            }
            .listRowBackground(selectedTab == 0 ? Color.blue.opacity(0.1) : Color.clear)
            
            Button(action: { selectedTab = 1 }) {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .foregroundColor(selectedTab == 1 ? .blue : .primary)
                    Text("Accounts")
                        .foregroundColor(selectedTab == 1 ? .blue : .primary)
                    Spacer()
                }
            }
            .listRowBackground(selectedTab == 1 ? Color.blue.opacity(0.1) : Color.clear)
            
            Button(action: { selectedTab = 2 }) {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(selectedTab == 2 ? .blue : .primary)
                    Text("Settings")
                        .foregroundColor(selectedTab == 2 ? .blue : .primary)
                    Spacer()
                }
            }
            .listRowBackground(selectedTab == 2 ? Color.blue.opacity(0.1) : Color.clear)
        }
        .navigationTitle("Halo Fi")
        .listStyle(SidebarListStyle())
    }
}

// MARK: - iPad Detail View
struct DetailView: View {
    let selectedTab: Int
    
    var body: some View {
        Group {
            switch selectedTab {
            case 0:
                HomeView()
            case 1:
                AccountsOverviewView()
            case 2:
                SettingsView()
            default:
                HomeView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    MainTabView()
} 