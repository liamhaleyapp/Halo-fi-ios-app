//
//  AboutHeader.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - About Header Component
struct AboutHeader: View {
    let onBack: () -> Void

    var body: some View {
        NavigationHeader(title: "About", onBack: onBack, style: .dark)
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        AboutHeader(onBack: {})
    }
}
