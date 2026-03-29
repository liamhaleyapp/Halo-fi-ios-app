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
    @AppStorage("themeMode") private var themeMode: String = "Dark"

    var body: some View {
        MainTabView()
            .dynamicTypeSize(.large ... .accessibility3)
            .environment(\.haloHighContrast, themeMode == "High-Contrast")
    }
}

#Preview {
    ContentView()
}
