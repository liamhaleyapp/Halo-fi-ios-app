import SwiftUI

struct HomeView: View {
    @Environment(\.userManager) private var userManager
    @State private var showingVoiceConversation = false
    
    private var userName: String {
        userManager.currentUser?.firstName ?? "User"
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 10) {
                        // Greeting
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hello, \(userName)")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, max(20, geometry.size.width * 0.05))
                        .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 20 : 65)
                    
                        // Central voice button with responsive sizing
                        VStack(spacing: 16) {
                            Button(action: {
                                showingVoiceConversation = true
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 160 : 120, 
                                               height: UIDevice.current.userInterfaceIdiom == .pad ? 160 : 120)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [Color.blue, Color.purple],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 3
                                                )
                                        )
                                        .shadow(color: .blue.opacity(0.5), radius: 20, x: 0, y: 0)
                                    
                                    // Mic icon for voice conversation
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: UIDevice.current.userInterfaceIdiom == .pad ? 70 : 50, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Text("Tap to start conversation")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(UIDevice.current.userInterfaceIdiom == .pad ? 120 : 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        
                        // Action buttons with responsive layout
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            // iPad grid layout
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 16) {
                                ActionButton(
                                    title: "Daily Snapshot",
                                    gradient: LinearGradient(
                                        colors: [Color.indigo, Color.purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                ) {
                                    // TODO: Navigate to Daily Snapshot
                                }
                                
                                ActionButton(
                                    title: "Weekly Summary",
                                    gradient: LinearGradient(
                                        colors: [Color.teal, Color.blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                ) {
                                    // TODO: Navigate to Weekly Summary
                                }
                                
                                ActionButton(
                                    title: "Spending Check",
                                    gradient: LinearGradient(
                                        colors: [Color.teal.opacity(0.8), Color.cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                ) {
                                    // TODO: Navigate to Spending Check
                                }
                                
                                ActionButton(
                                    title: "Financial Coaching",
                                    gradient: LinearGradient(
                                        colors: [Color.white.opacity(0.9), Color.gray.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                ) {
                                    // TODO: Navigate to Financial Coaching
                                }
                            }
                            .padding(.horizontal, max(20, geometry.size.width * 0.1))
                        } else {
                            // iPhone single column layout
                            VStack(spacing: 8) {
                                ActionButton(
                                    title: "Daily Snapshot",
                                    gradient: LinearGradient(
                                        colors: [Color.indigo, Color.purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                ) {
                                    // TODO: Navigate to Daily Snapshot
                                }
                                
                                ActionButton(
                                    title: "Weekly Summary",
                                    gradient: LinearGradient(
                                        colors: [Color.teal, Color.blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                ) {
                                    // TODO: Navigate to Weekly Summary
                                }
                                
                                ActionButton(
                                    title: "Spending Check",
                                    gradient: LinearGradient(
                                        colors: [Color.teal.opacity(0.8), Color.cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                ) {
                                    // TODO: Navigate to Spending Check
                                }
                                
                                ActionButton(
                                    title: "Financial Coaching",
                                    gradient: LinearGradient(
                                        colors: [Color.white.opacity(0.9), Color.gray.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                ) {
                                    // TODO: Navigate to Financial Coaching
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showingVoiceConversation) {
            VoiceConversationView()
        }
    }
}

struct ActionButton: View {
    let title: String
    let gradient: LinearGradient
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(gradient)
            .cornerRadius(16)
        }
    }
}

#Preview {
    HomeView()
} 