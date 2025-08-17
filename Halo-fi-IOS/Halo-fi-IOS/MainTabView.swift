import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView {
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
}

#Preview {
    MainTabView()
} 