//
//  HaloFiLogo.swift
//  Halo-fi-IOS
//
//  Reusable HaloFi logo component. Loads from bundle resource.
//

import SwiftUI
import UIKit

struct HaloFiLogo: View {
    let size: CGFloat

    var body: some View {
        if let url = Bundle.main.url(forResource: "halofi_logo", withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
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
