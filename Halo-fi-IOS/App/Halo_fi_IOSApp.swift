//
//  Halo_fi_IOSApp.swift
//  Halo-fi-IOS
//
//  Created by Liam Haley on 8/14/25.
//

import SwiftUI

@main
struct Halo_fi_IOSApp: App {
  @State private var userManager = UserManager()
  @StateObject private var permissionManager = PermissionManager.shared
  
  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(userManager)
        .environmentObject(permissionManager)
        .onAppear {
          // Request microphone permission early for accessibility
          Task {
            if permissionManager.microphonePermission == .notDetermined {
              _ = await permissionManager.requestMicrophonePermission()
            }
          }
        }
    }
  }
}
