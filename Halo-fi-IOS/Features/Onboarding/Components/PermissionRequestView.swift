//
//  PermissionRequestView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/16/25.
//

import SwiftUI

struct PermissionRequestView: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var isRequestingPermission = false
    @State private var showingSettingsAlert = false
    
    let onPermissionGranted: () -> Void
    let onSkip: (() -> Void)?
    
    init(onPermissionGranted: @escaping () -> Void, onSkip: (() -> Void)? = nil) {
        self.onPermissionGranted = onPermissionGranted
        self.onSkip = onSkip
    }
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Enable Voice Access")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Halo uses your microphone to provide voice assistance. This is essential for users with vision impairments.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Benefits list
            VStack(alignment: .leading, spacing: 12) {
                PermissionBenefitRow(
                    icon: "waveform",
                    title: "Voice Commands",
                    description: "Control the app with your voice"
                )
                
                PermissionBenefitRow(
                    icon: "speaker.wave.2",
                    title: "Audio Feedback",
                    description: "Get spoken responses and confirmations"
                )
                
                PermissionBenefitRow(
                    icon: "accessibility",
                    title: "Accessibility First",
                    description: "Designed for users with vision impairments"
                )
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 16) {
                Button(action: requestPermission) {
                    HStack {
                        if isRequestingPermission {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "mic.fill")
                        }
                        Text(isRequestingPermission ? "Requesting..." : "Enable Microphone")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isRequestingPermission)
                
                if let onSkip = onSkip {
                    Button("Skip for Now", action: onSkip)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .onChange(of: permissionManager.microphonePermission) { _, newStatus in
            if newStatus == .granted {
                onPermissionGranted()
            }
        }
        .alert("Microphone Permission Required", isPresented: $showingSettingsAlert) {
            Button("Open Settings") {
                permissionManager.openAppSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable microphone access in Settings to use voice features.")
        }
    }
    
    private func requestPermission() {
        isRequestingPermission = true
        
        Task {
            let status = await permissionManager.requestMicrophonePermission()
            
            await MainActor.run {
                isRequestingPermission = false
                
                if status == .denied {
                    showingSettingsAlert = true
                }
            }
        }
    }
}

struct PermissionBenefitRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    PermissionRequestView(
        onPermissionGranted: { print("Permission granted") },
        onSkip: { print("Skipped") }
    )
}

