//
//  HaloFiLogo.swift
//  Halo-fi-IOS
//
//  Reusable HaloFi logo component. Loads from bundle resource.
//

import SwiftUI

struct HaloFiLogo: View {
    let size: CGFloat

    var body: some View {
        Image("HaloFiLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 20) {
            HaloFiLogo(size: 120)
            HaloFiLogo(size: 80)
        }
    }
}
