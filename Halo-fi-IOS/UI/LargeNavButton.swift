import SwiftUI

struct LargeNavButton: View {
    let title: String
    let icon: String
    let tileColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tileColor)
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
            }
            
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(16)
    }
}

#Preview {
    ZStack { Color.black.ignoresSafeArea() }
        .overlay(
            LargeNavButton(
                title: "Preview Button",
                icon: "creditcard.fill",
                tileColor: .blue
            )
            .padding()
        )
}


