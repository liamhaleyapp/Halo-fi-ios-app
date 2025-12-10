//
//  PreferencesHeader.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct PreferencesHeader: View {
    let onBack: () -> Void

    var body: some View {
        NavigationHeader(title: "Preferences", onBack: onBack, style: .light)
    }
}

#Preview {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        PreferencesHeader(onBack: {})
    }
}
