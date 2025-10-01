//
//  OnboardingPage.swift
//  Halo-fi-IOS
//
//  Created by Christopher Koski on 10/1/25.
//

import SwiftUI

// MARK: - Onboarding Page Model
struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let color: [Color]
}
