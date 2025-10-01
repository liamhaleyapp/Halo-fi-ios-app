//
//  ActionButton.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Action Button Component
struct ActionButton: View {
    let title: String
    let gradient: LinearGradient
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(gradient)
                .cornerRadius(16)
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 16) {
            ActionButton(
                title: "Daily Snapshot",
                gradient: LinearGradient(
                    colors: [Color.indigo, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            ) {}
            
            ActionButton(
                title: "Weekly Summary",
                gradient: LinearGradient(
                    colors: [Color.teal, Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            ) {}
        }
        .padding()
    }
}