import SwiftUI

struct VoiceConversationView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var isMuted = false
    @State private var isListening = true
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0.0
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header text at top
                Text("Hi, I'm Halo. How can I help you?")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 60)
                    .padding(.bottom, 20)
                
                Spacer()
                
                // Central animated graphics - centered on page
                ZStack {
                    // Outer pulsing circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 200, height: 200)
                        .scaleEffect(pulseScale)
                        .opacity(0.6)
                        .animation(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                    
                    // Middle rotating ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(rotationAngle))
                        .animation(
                            Animation.linear(duration: 8.0)
                                .repeatForever(autoreverses: false),
                            value: rotationAngle
                        )
                    
                    // Inner microphone icon
                    Image(systemName: "mic.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .frame(width: 120, height: 120)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 4
                                )
                        )
                        .shadow(color: .blue.opacity(0.5), radius: 30, x: 0, y: 0)
                }
                
                // Status text below mic graphic
                Text(isListening ? "Listening..." : "Muted")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.top, 30)
                    .opacity(isListening ? 1.0 : 0.7)
                
                Spacer()
                
                // Control buttons at bottom
                HStack(spacing: 40) {
                    // Mute button
                    Button(action: {
                        isMuted.toggle()
                        isListening.toggle()
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                            Text(isMuted ? "Unmute" : "Mute")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(width: 100, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: isMuted ? 
                                            [Color.orange.opacity(0.8), Color.red.opacity(0.8)] :
                                            [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: isMuted ? 
                                            [Color.orange, Color.red] :
                                            [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )
                    }
                    
                    // End button
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                            Text("End")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(width: 100, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.red.opacity(0.8), Color.pink.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.red, Color.pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            // Start animations
            pulseScale = 1.2
            rotationAngle = 360
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    VoiceConversationView()
} 