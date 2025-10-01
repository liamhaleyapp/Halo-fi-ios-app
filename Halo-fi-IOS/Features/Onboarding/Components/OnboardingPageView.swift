//
//  OnboardingPageView.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Onboarding Page View Component
struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Circle()
                .fill(LinearGradient(colors: page.color, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: page.icon)
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                )
            
            // Text Content
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 20)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingPageView(page: MockOnboardingData.pages[0])
    }
}
