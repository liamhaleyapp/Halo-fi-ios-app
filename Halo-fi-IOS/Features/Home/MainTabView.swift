import SwiftUI

struct MainTabView: View {
    @Environment(UserManager.self) private var userManager
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
      } else {
        OnboardingView()
      }
        }
    }
}

#Preview {
  MainTabView()
}
