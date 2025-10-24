//
//  PermissionManager.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/16/25.
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var microphonePermission: PermissionStatus = .notDetermined
    @Published var allPermissionsGranted = false
    
    private init() {
        checkMicrophonePermission()
    }
    
    // MARK: - Microphone Permission
    
    func requestMicrophonePermission() async -> PermissionStatus {
        let status = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        
        let permissionStatus: PermissionStatus = status ? .granted : .denied
        microphonePermission = permissionStatus
        updateAllPermissionsStatus()
        
        return permissionStatus
    }
    
    private func checkMicrophonePermission() {
        let status = AVAudioSession.sharedInstance().recordPermission
        switch status {
        case .granted:
            microphonePermission = .granted
        case .denied:
            microphonePermission = .denied
        case .undetermined:
            microphonePermission = .notDetermined
        @unknown default:
            microphonePermission = .notDetermined
        }
        updateAllPermissionsStatus()
    }
    
    private func updateAllPermissionsStatus() {
        allPermissionsGranted = microphonePermission == .granted
    }
    
    // MARK: - Permission Status Helpers
    
    var isMicrophonePermissionGranted: Bool {
        microphonePermission == .granted
    }
    
    var shouldShowPermissionAlert: Bool {
        microphonePermission == .denied
    }
    
    func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - Permission Status Enum

enum PermissionStatus: String, CaseIterable {
    case notDetermined = "notDetermined"
    case granted = "granted"
    case denied = "denied"
    
    var displayName: String {
        switch self {
        case .notDetermined:
            return "Not Requested"
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        }
    }
    
    var isGranted: Bool {
        self == .granted
    }
}

