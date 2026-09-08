//
//  ContentView.swift
//  Halo-fi-IOS
//
//  Created by Liam Haley on 8/14/25.
//

import SwiftUI

// MARK: - High Contrast Environment Key

private struct HaloHighContrastKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var haloHighContrast: Bool {
        get { self[HaloHighContrastKey.self] }
        set { self[HaloHighContrastKey.self] = newValue }
    }
}

// MARK: - Content View

struct ContentView: View {
    // Must match the default in Halo_fi_IOSApp / PreferencesView. Now that
    // the UI is fully adaptive, "System" (follow the OS) is the default.
    @AppStorage("themeMode") private var themeMode: String = "System"

    var body: some View {
        Group {
            #if DEBUG
            if UITestArchetype.isActive, ProcessInfo.processInfo.arguments.contains("--ui-test-bank-intro") {
                BankIntroFixtureHost()
            } else if UITestArchetype.isActive,
               let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-test-checkout=") }) {
                CheckoutFixtureHost(mode: String(argument.dropFirst("--ui-test-checkout=".count)))
            } else {
                MainTabView()
            }
            #else
            MainTabView()
            #endif
        }
        .environment(\.haloHighContrast, themeMode == "High-Contrast")
    }
}

#Preview {
    ContentView()
}
