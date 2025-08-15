import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Navigation bar
                    HStack {
                        Spacer()
                        
                        Text("Settings")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Settings options
                    ScrollView {
                        VStack(spacing: 16) {
                            SettingsOption(
                                icon: "person.fill",
                                title: "Profile",
                                action: {
                                    // TODO: Navigate to Profile
                                }
                            )
                            
                            SettingsOption(
                                icon: "hexagon.fill",
                                title: "Preferences",
                                action: {
                                    // TODO: Navigate to Preferences
                                }
                            )
                            
                            SettingsOption(
                                icon: "diamond.fill",
                                title: "Subscription",
                                action: {
                                    // TODO: Navigate to Subscription
                                }
                            )
                            
                            SettingsOption(
                                icon: "person.2.fill",
                                title: "Invite Friends",
                                action: {
                                    // TODO: Navigate to Invite Friends
                                }
                            )
                            
                            SettingsOption(
                                icon: "info.circle.fill",
                                title: "About",
                                action: {
                                    // TODO: Navigate to About
                                }
                            )
                            
                            SettingsOption(
                                icon: "rectangle.portrait.and.arrow.right",
                                title: "Logout",
                                action: {
                                    // TODO: Implement logout
                                }
                            )
                            
                            SettingsOption(
                                icon: "person.fill",
                                title: "Account",
                                action: {
                                    // TODO: Navigate to Account
                                }
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct SettingsOption: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                
                Text(title)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
        }
    }
}

#Preview {
    SettingsView()
} 