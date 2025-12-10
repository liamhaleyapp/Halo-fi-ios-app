//
//  ProfileHeader.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

struct ProfileHeader: View {
    let onBack: () -> Void

    var body: some View {
        NavigationHeader(title: "Profile", onBack: onBack, style: .dark)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ProfileHeader(onBack: {})
    }
}
