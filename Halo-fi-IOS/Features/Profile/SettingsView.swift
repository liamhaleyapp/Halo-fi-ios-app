//
//  SettingsView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(UserManager.self) private var userManager
    @State private var showingProfile = false
    @State private var showingPreferences = false
    @State private var showingSubscription = false
    @State private var showingInviteFriends = false
    @State private var showingAbout = false
    @State private var showingAccounts = false
    
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
                        VStack(spacing: 8) {
                            SettingsOption(
                                icon: "person.fill",
                                title: "Profile",
                                action: {
                                    showingProfile = true
                                }
                            )
                            
                            SettingsOption(
                                icon: "hexagon.fill",
                                title: "Preferences",
                                action: {
                                    showingPreferences = true
                                }
                            )
                            
                            SettingsOption(
                                icon: "diamond.fill",
                                title: "Subscription",
                                action: {
                                    showingSubscription = true
                                }
                            )
                            
                            SettingsOption(
                                icon: "person.2.fill",
                                title: "Invite Friends",
                                action: {
                                    showingInviteFriends = true
                                }
                            )
                            
                            SettingsOption(
                                icon: "person.fill",
                                title: "Accounts",
                                action: {
                                    showingAccounts = true
                                }
                            )
                            
                            SettingsOption(
                                icon: "info.circle.fill",
                                title: "About",
                                action: {
                                    showingAbout = true
                                }
                            )
                            
                            SettingsOption(
                                icon: "rectangle.portrait.and.arrow.right",
                                title: "Logout",
                                action: {
                                    userManager.signOut()
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
        .fullScreenCover(isPresented: $showingProfile) {
            ProfileView()
        }
        .fullScreenCover(isPresented: $showingPreferences) {
            PreferencesView()
        }
        .fullScreenCover(isPresented: $showingSubscription) {
            SubscriptionView()
        }
        .fullScreenCover(isPresented: $showingInviteFriends) {
            InviteFriendsView()
        }
        .fullScreenCover(isPresented: $showingAbout) {
            AboutView()
        }
        .fullScreenCover(isPresented: $showingAccounts) {
            AccountsView()
        }
    }
}

#Preview {
    SettingsView()
} 
